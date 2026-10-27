// Package store keeps users, sessions and devices in a single JSON file.
package store

import (
	"crypto/rand"
	"crypto/sha256"
	"crypto/subtle"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"math/big"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"sync"
	"time"

	"golang.org/x/crypto/bcrypt"
)

var (
	ErrExists      = errors.New("exists")
	ErrNotFound    = errors.New("not found")
	ErrBadPassword = errors.New("bad password")
)

var dummyHash, _ = bcrypt.GenerateFromPassword([]byte("pgl-dummy"), bcrypt.DefaultCost)

type User struct {
	Email    string    `json:"email"`
	PassHash string    `json:"pass_hash"`
	Admin    bool      `json:"admin,omitempty"`
	Created  time.Time `json:"created"`
}

type Token struct {
	Email   string    `json:"email"`
	Created time.Time `json:"created"`
	Expires time.Time `json:"expires"`
}

type Device struct {
	ID         string    `json:"id"`
	SecretHash string    `json:"secret_hash"`
	Name       string    `json:"name"`
	OS         string    `json:"os"`
	Owner      string    `json:"owner,omitempty"`
	Created    time.Time `json:"created"`
	LastSeen   time.Time `json:"last_seen"`
}

type data struct {
	Users   map[string]*User   `json:"users"`
	Tokens  map[string]*Token  `json:"tokens"` // key: sha256(token)
	Devices map[string]*Device `json:"devices"`
	Secret  string             `json:"secret"` // TURN shared secret
}

type Store struct {
	mu   sync.Mutex
	path string
	d    data
}

func Open(path string) (*Store, error) {
	s := &Store{path: path}
	s.d.Users = map[string]*User{}
	s.d.Tokens = map[string]*Token{}
	s.d.Devices = map[string]*Device{}
	b, err := os.ReadFile(path)
	if err == nil {
		if err := json.Unmarshal(b, &s.d); err != nil {
			return nil, fmt.Errorf("read %s: %w", path, err)
		}
	} else if !os.IsNotExist(err) {
		return nil, err
	}
	if s.d.Users == nil {
		s.d.Users = map[string]*User{}
	}
	if s.d.Tokens == nil {
		s.d.Tokens = map[string]*Token{}
	}
	if s.d.Devices == nil {
		s.d.Devices = map[string]*Device{}
	}
	if s.d.Secret == "" {
		s.d.Secret = RandHex(32)
	}
	return s, s.saveLocked()
}

func (s *Store) saveLocked() error {
	b, err := json.MarshalIndent(&s.d, "", " ")
	if err != nil {
		return err
	}
	if err := os.MkdirAll(filepath.Dir(s.path), 0o700); err != nil {
		return err
	}
	tmp := s.path + ".tmp"
	if err := os.WriteFile(tmp, b, 0o600); err != nil {
		return err
	}
	return os.Rename(tmp, s.path)
}

func (s *Store) TurnSecret() string {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.d.Secret
}

func RandHex(n int) string {
	b := make([]byte, n)
	if _, err := rand.Read(b); err != nil {
		panic(err)
	}
	return hex.EncodeToString(b)
}

func hashToken(t string) string {
	h := sha256.Sum256([]byte(t))
	return hex.EncodeToString(h[:])
}

func NormEmail(e string) string { return strings.ToLower(strings.TrimSpace(e)) }

// CreateUser registers a new account. The first account becomes admin.
func (s *Store) CreateUser(email, password string) (*User, error) {
	email = NormEmail(email)
	h, err := bcrypt.GenerateFromPassword([]byte(password), bcrypt.DefaultCost)
	if err != nil {
		return nil, err
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	if _, ok := s.d.Users[email]; ok {
		return nil, ErrExists
	}
	u := &User{Email: email, PassHash: string(h), Admin: len(s.d.Users) == 0, Created: time.Now()}
	s.d.Users[email] = u
	return u, s.saveLocked()
}

func (s *Store) CheckPassword(email, password string) (*User, error) {
	email = NormEmail(email)
	s.mu.Lock()
	u, ok := s.d.Users[email]
	s.mu.Unlock()
	if !ok {
		// equalize timing with a real comparison
		_ = bcrypt.CompareHashAndPassword(dummyHash, []byte(password))
		return nil, ErrBadPassword
	}
	if bcrypt.CompareHashAndPassword([]byte(u.PassHash), []byte(password)) != nil {
		return nil, ErrBadPassword
	}
	return u, nil
}

func (s *Store) SetPassword(email, password string) error {
	h, err := bcrypt.GenerateFromPassword([]byte(password), bcrypt.DefaultCost)
	if err != nil {
		return err
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	u, ok := s.d.Users[NormEmail(email)]
	if !ok {
		return ErrNotFound
	}
	u.PassHash = string(h)
	for k, t := range s.d.Tokens {
		if t.Email == u.Email {
			delete(s.d.Tokens, k)
		}
	}
	return s.saveLocked()
}

func (s *Store) NewToken(email string) (string, error) {
	t := RandHex(32)
	s.mu.Lock()
	defer s.mu.Unlock()
	now := time.Now()
	for k, v := range s.d.Tokens {
		if now.After(v.Expires) {
			delete(s.d.Tokens, k)
		}
	}
	s.d.Tokens[hashToken(t)] = &Token{Email: NormEmail(email), Created: now, Expires: now.Add(90 * 24 * time.Hour)}
	return t, s.saveLocked()
}

func (s *Store) UserByToken(t string) (*User, bool) {
	if t == "" {
		return nil, false
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	tk, ok := s.d.Tokens[hashToken(t)]
	if !ok || time.Now().After(tk.Expires) {
		return nil, false
	}
	u, ok := s.d.Users[tk.Email]
	return u, ok
}

func (s *Store) DeleteToken(t string) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	delete(s.d.Tokens, hashToken(t))
	return s.saveLocked()
}

// NewDevice allocates a unique 9-digit ID and a secret for a new installation.
func (s *Store) NewDevice(name, osName string) (*Device, string, error) {
	secret := RandHex(24)
	s.mu.Lock()
	defer s.mu.Unlock()
	var id string
	for {
		n, err := rand.Int(rand.Reader, big.NewInt(900_000_000))
		if err != nil {
			return nil, "", err
		}
		id = fmt.Sprintf("%d", 100_000_000+n.Int64())
		if _, ok := s.d.Devices[id]; !ok {
			break
		}
	}
	d := &Device{ID: id, SecretHash: hashToken(secret), Name: limit(name, 64), OS: limit(osName, 32), Created: time.Now()}
	s.d.Devices[id] = d
	return d, secret, s.saveLocked()
}

func (s *Store) CheckDevice(id, secret string) (*Device, bool) {
	s.mu.Lock()
	defer s.mu.Unlock()
	d, ok := s.d.Devices[id]
	if !ok {
		return nil, false
	}
	if subtle.ConstantTimeCompare([]byte(d.SecretHash), []byte(hashToken(secret))) != 1 {
		return nil, false
	}
	return d, true
}

func (s *Store) Device(id string) (Device, bool) {
	s.mu.Lock()
	defer s.mu.Unlock()
	d, ok := s.d.Devices[id]
	if !ok {
		return Device{}, false
	}
	return *d, true
}

func (s *Store) TouchDevice(id, name, osName string) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if d, ok := s.d.Devices[id]; ok {
		d.LastSeen = time.Now()
		if name != "" {
			d.Name = limit(name, 64)
		}
		if osName != "" {
			d.OS = limit(osName, 32)
		}
		_ = s.saveLocked()
	}
}

func (s *Store) SetOwner(id, email string) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	d, ok := s.d.Devices[id]
	if !ok {
		return ErrNotFound
	}
	d.Owner = NormEmail(email)
	return s.saveLocked()
}

func (s *Store) DevicesOf(email string) []Device {
	email = NormEmail(email)
	s.mu.Lock()
	defer s.mu.Unlock()
	var out []Device
	for _, d := range s.d.Devices {
		if d.Owner == email {
			out = append(out, *d)
		}
	}
	sort.Slice(out, func(i, j int) bool { return out[i].Name < out[j].Name })
	return out
}

func limit(s string, n int) string {
	s = strings.TrimSpace(s)
	r := []rune(s)
	if len(r) > n {
		return string(r[:n])
	}
	return s
}
