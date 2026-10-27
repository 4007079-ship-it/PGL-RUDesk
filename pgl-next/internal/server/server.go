package server

import (
	"encoding/json"
	"io/fs"
	"log"
	"net/http"
	"strings"
	"time"

	"github.com/gorilla/websocket"

	"pgl-next/internal/proto"
	"pgl-next/internal/store"
)

// Config holds runtime options for the server.
type Config struct {
	Addr     string // HTTP listen address, e.g. ":21220"
	PublicIP string // public IP announced for TURN relay
	Host     string // hostname clients use to reach STUN/TURN (domain or IP)
	Realm    string
	TurnPort int
	RelayMin int // lowest UDP port used for TURN relay allocations
	RelayMax int // highest UDP port used for TURN relay allocations
	DataFile string
	Web      fs.FS // embedded web assets (may be nil)
}

type Server struct {
	cfg  Config
	st   *store.Store
	hub  *hub
	turn *turnServer
	up   websocket.Upgrader
}

func New(cfg Config) (*Server, error) {
	st, err := store.Open(cfg.DataFile)
	if err != nil {
		return nil, err
	}
	s := &Server{
		cfg: cfg,
		st:  st,
		hub: newHub(),
		up:  websocket.Upgrader{CheckOrigin: func(*http.Request) bool { return true }},
	}
	if cfg.PublicIP != "" {
		rmin, rmax := cfg.RelayMin, cfg.RelayMax
		if rmin == 0 || rmax == 0 || rmin > rmax {
			rmin, rmax = 21300, 21400
		}
		ts, err := startTURN(cfg.PublicIP, cfg.Realm, st.TurnSecret(), cfg.TurnPort, rmin, rmax)
		if err != nil {
			log.Printf("turn disabled: %v", err)
		} else {
			s.turn = ts
		}
	}
	return s, nil
}

func (s *Server) Close() error {
	if s.turn != nil {
		return s.turn.Close()
	}
	return nil
}

func (s *Server) Handler() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("/ws/device", s.wsDevice)
	mux.HandleFunc("/ws/viewer", s.wsViewer)
	mux.HandleFunc("/api/register", s.apiRegister)
	mux.HandleFunc("/api/login", s.apiLogin)
	mux.HandleFunc("/api/logout", s.apiLogout)
	mux.HandleFunc("/api/me", s.apiMe)
	mux.HandleFunc("/api/password", s.apiPassword)
	mux.HandleFunc("/api/devices", s.apiDevices)
	mux.HandleFunc("/api/device/claim", s.apiClaim)
	mux.HandleFunc("/api/device/new", s.apiNewDevice)
	mux.HandleFunc("/api/device/status", s.apiDeviceStatus)
	mux.HandleFunc("/healthz", func(w http.ResponseWriter, _ *http.Request) { w.Write([]byte("ok")) })
	if s.cfg.Web != nil {
		mux.Handle("/", http.FileServer(http.FS(s.cfg.Web)))
	}
	return logMiddleware(mux)
}

func logMiddleware(h http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		h.ServeHTTP(w, r)
	})
}

// --- helpers ---

func writeJSON(w http.ResponseWriter, code int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(code)
	_ = json.NewEncoder(w).Encode(v)
}

func errJSON(w http.ResponseWriter, code int, msg string) {
	writeJSON(w, code, map[string]string{"error": msg})
}

func (s *Server) userFromReq(r *http.Request) (*store.User, string, bool) {
	tok := ""
	if h := r.Header.Get("Authorization"); strings.HasPrefix(h, "Bearer ") {
		tok = strings.TrimPrefix(h, "Bearer ")
	}
	if tok == "" {
		if c, err := r.Cookie("pgl_token"); err == nil {
			tok = c.Value
		}
	}
	u, ok := s.st.UserByToken(tok)
	return u, tok, ok
}

type credReq struct {
	Email    string `json:"email"`
	Password string `json:"password"`
}

func readJSON(r *http.Request, v any) error {
	return json.NewDecoder(http.MaxBytesReader(nil, r.Body, 1<<20)).Decode(v)
}

// --- account API ---

func (s *Server) apiRegister(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		errJSON(w, 405, "method")
		return
	}
	var c credReq
	if readJSON(r, &c) != nil || !validEmail(c.Email) || len(c.Password) < 6 {
		errJSON(w, 400, "Проверьте почту и пароль (минимум 6 символов).")
		return
	}
	if _, err := s.st.CreateUser(c.Email, c.Password); err != nil {
		if err == store.ErrExists {
			errJSON(w, 409, "Такой пользователь уже есть.")
			return
		}
		errJSON(w, 500, "server")
		return
	}
	s.issueToken(w, c.Email)
}

func (s *Server) apiLogin(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		errJSON(w, 405, "method")
		return
	}
	var c credReq
	if readJSON(r, &c) != nil {
		errJSON(w, 400, "bad")
		return
	}
	if _, err := s.st.CheckPassword(c.Email, c.Password); err != nil {
		errJSON(w, 401, "Неверная почта или пароль.")
		return
	}
	s.issueToken(w, c.Email)
}

func (s *Server) issueToken(w http.ResponseWriter, email string) {
	tok, err := s.st.NewToken(email)
	if err != nil {
		errJSON(w, 500, "server")
		return
	}
	http.SetCookie(w, &http.Cookie{
		Name: "pgl_token", Value: tok, Path: "/", HttpOnly: true,
		SameSite: http.SameSiteLaxMode, MaxAge: 90 * 24 * 3600,
	})
	writeJSON(w, 200, map[string]string{"token": tok, "email": store.NormEmail(email)})
}

func (s *Server) apiLogout(w http.ResponseWriter, r *http.Request) {
	_, tok, _ := s.userFromReq(r)
	_ = s.st.DeleteToken(tok)
	http.SetCookie(w, &http.Cookie{Name: "pgl_token", Value: "", Path: "/", MaxAge: -1})
	writeJSON(w, 200, map[string]bool{"ok": true})
}

func (s *Server) apiMe(w http.ResponseWriter, r *http.Request) {
	u, _, ok := s.userFromReq(r)
	if !ok {
		errJSON(w, 401, "auth")
		return
	}
	writeJSON(w, 200, map[string]any{"email": u.Email, "admin": u.Admin})
}

func (s *Server) apiPassword(w http.ResponseWriter, r *http.Request) {
	u, _, ok := s.userFromReq(r)
	if !ok {
		errJSON(w, 401, "auth")
		return
	}
	var body struct{ Old, New string }
	if readJSON(r, &body) != nil || len(body.New) < 6 {
		errJSON(w, 400, "Новый пароль слишком короткий.")
		return
	}
	if _, err := s.st.CheckPassword(u.Email, body.Old); err != nil {
		errJSON(w, 401, "Текущий пароль неверен.")
		return
	}
	if err := s.st.SetPassword(u.Email, body.New); err != nil {
		errJSON(w, 500, "server")
		return
	}
	writeJSON(w, 200, map[string]bool{"ok": true})
}

type deviceView struct {
	ID       string `json:"id"`
	Name     string `json:"name"`
	OS       string `json:"os"`
	Online   bool   `json:"online"`
	LastSeen int64  `json:"last_seen"`
}

func (s *Server) apiDevices(w http.ResponseWriter, r *http.Request) {
	u, _, ok := s.userFromReq(r)
	if !ok {
		errJSON(w, 401, "auth")
		return
	}
	devs := s.st.DevicesOf(u.Email)
	out := make([]deviceView, 0, len(devs))
	for _, d := range devs {
		seen := int64(0)
		if !d.LastSeen.IsZero() {
			seen = d.LastSeen.Unix()
		}
		out = append(out, deviceView{
			ID: d.ID, Name: d.Name, OS: d.OS,
			Online: s.hub.deviceOnline(d.ID), LastSeen: seen,
		})
	}
	writeJSON(w, 200, out)
}

// apiClaim links an existing device to the logged-in account by id + secret.
func (s *Server) apiClaim(w http.ResponseWriter, r *http.Request) {
	u, _, ok := s.userFromReq(r)
	if !ok {
		errJSON(w, 401, "auth")
		return
	}
	var body struct{ ID, Secret string }
	if readJSON(r, &body) != nil {
		errJSON(w, 400, "bad")
		return
	}
	if _, ok := s.st.CheckDevice(body.ID, body.Secret); !ok {
		errJSON(w, 404, "Устройство не найдено или ключ неверный.")
		return
	}
	if err := s.st.SetOwner(body.ID, u.Email); err != nil {
		errJSON(w, 500, "server")
		return
	}
	writeJSON(w, 200, map[string]bool{"ok": true})
}

func (s *Server) apiDeviceStatus(w http.ResponseWriter, r *http.Request) {
	id := r.URL.Query().Get("id")
	writeJSON(w, 200, map[string]bool{"online": s.hub.deviceOnline(id)})
}

func validEmail(e string) bool {
	e = store.NormEmail(e)
	at := strings.IndexByte(e, '@')
	return at > 0 && strings.IndexByte(e[at+1:], '.') > 0 && len(e) <= 254
}

func (s *Server) ice(ttl time.Duration) []proto.ICEServer {
	if s.turn == nil {
		return []proto.ICEServer{{URLs: []string{"stun:" + s.cfg.Host + ":" + itoa(s.cfg.TurnPort)}}}
	}
	return s.turn.iceServers(s.cfg.Host, ttl)
}
