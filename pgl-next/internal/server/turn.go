package server

import (
	"net"
	"time"

	"github.com/pion/logging"
	"github.com/pion/turn/v4"

	"pgl-next/internal/proto"
)

// turnServer wraps a pion TURN server that authenticates viewers and devices
// with short-lived credentials derived from a shared secret (TURN REST API).
type turnServer struct {
	srv    *turn.Server
	secret string
	realm  string
	pubIP  string
	port   int
}

func startTURN(publicIP, realm, secret string, port, relayMin, relayMax int) (*turnServer, error) {
	udp, err := net.ListenPacket("udp4", "0.0.0.0:"+itoa(port))
	if err != nil {
		return nil, err
	}
	gen := &turn.RelayAddressGeneratorPortRange{
		RelayAddress: net.ParseIP(publicIP),
		Address:      "0.0.0.0",
		MinPort:      uint16(relayMin),
		MaxPort:      uint16(relayMax),
	}
	srv, err := turn.NewServer(turn.ServerConfig{
		Realm:         realm,
		AuthHandler:   turn.NewLongTermAuthHandler(secret, nil),
		LoggerFactory: logging.NewDefaultLoggerFactory(),
		PacketConnConfigs: []turn.PacketConnConfig{
			{PacketConn: udp, RelayAddressGenerator: gen},
		},
	})
	if err != nil {
		_ = udp.Close()
		return nil, err
	}
	return &turnServer{srv: srv, secret: secret, realm: realm, pubIP: publicIP, port: port}, nil
}

func (t *turnServer) Close() error {
	if t == nil || t.srv == nil {
		return nil
	}
	return t.srv.Close()
}

// iceServers builds the ICE server list for a client: the STUN/TURN endpoint
// with a credential valid for the given lifetime.
func (t *turnServer) iceServers(host string, ttl time.Duration) []proto.ICEServer {
	stun := "stun:" + host + ":" + itoa(t.port)
	if t == nil {
		return []proto.ICEServer{{URLs: []string{stun}}}
	}
	user, pass, err := turn.GenerateLongTermCredentials(t.secret, ttl)
	if err != nil {
		return []proto.ICEServer{{URLs: []string{stun}}}
	}
	return []proto.ICEServer{
		{URLs: []string{stun}},
		{
			URLs:       []string{"turn:" + host + ":" + itoa(t.port) + "?transport=udp"},
			Username:   user,
			Credential: pass,
		},
	}
}

func itoa(n int) string {
	if n == 0 {
		return "0"
	}
	neg := n < 0
	if neg {
		n = -n
	}
	var b [20]byte
	i := len(b)
	for n > 0 {
		i--
		b[i] = byte('0' + n%10)
		n /= 10
	}
	if neg {
		i--
		b[i] = '-'
	}
	return string(b[i:])
}
