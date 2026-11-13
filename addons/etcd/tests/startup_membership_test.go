package etcd_test

import (
	"context"
	"fmt"
	"io"
	"log"
	"net"
	"net/http"
	"net/http/httptest"
	"net/http/httputil"
	"net/url"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"sort"
	"strings"
	"sync"
	"syscall"
	"testing"
	"time"
)

// A real three-member cluster uses these proxies as its advertised peer URLs.
// Only /members is fault-injected; Raft, version discovery, etc. are forwarded.
// This lets the test control a stale local membership observation while still
// requiring the joining etcd process to become healthy and replicate a write.
type peerProxy struct {
	server       *httptest.Server
	backend      string
	mu           sync.Mutex
	stale        []byte
	clusterID    string
	staleReads   int
	remaining    int
	unavailable  bool
	engineReads  int
	engineStales int
}

func loopbackURL(t *testing.T) string {
	t.Helper()
	l, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	addr := "http://" + l.Addr().String()
	l.Close()
	return addr
}

func newPeerProxy(t *testing.T) *peerProxy {
	t.Helper()
	p := &peerProxy{backend: loopbackURL(t)}
	u, _ := url.Parse(p.backend)
	proxy := httputil.NewSingleHostReverseProxy(u)
	proxy.ErrorLog = log.New(io.Discard, "", 0)
	p.server = httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/members" {
			p.mu.Lock()
			defer p.mu.Unlock()
			engine := strings.HasPrefix(r.UserAgent(), "Go-http-client/")
			if engine {
				p.engineReads++
			}
			if p.unavailable {
				http.Error(w, "membership endpoint unavailable", http.StatusServiceUnavailable)
				return
			}
			if p.remaining > 0 {
				if engine {
					p.engineStales++
				} else {
					p.staleReads++
					p.remaining--
				}
				w.Header().Set("X-Etcd-Cluster-ID", p.clusterID)
				w.Header().Set("Content-Type", "application/json")
				w.Write(p.stale)
				return
			}
		}
		proxy.ServeHTTP(w, r)
	}))
	t.Cleanup(p.server.Close)
	return p
}

type process struct {
	done chan struct{}
	log  string
}

func startProcess(t *testing.T, logPath string, command string, args []string, env []string) *process {
	t.Helper()
	f, err := os.Create(logPath)
	if err != nil {
		t.Fatal(err)
	}
	cmd := exec.Command(command, args...)
	cmd.Env = env
	cmd.Stdout, cmd.Stderr = f, f
	if err = cmd.Start(); err != nil {
		f.Close()
		t.Fatal(err)
	}
	p := &process{done: make(chan struct{}), log: logPath}
	go func() {
		cmd.Wait()
		f.Close()
		close(p.done)
	}()
	t.Cleanup(func() {
		cmd.Process.Signal(syscall.SIGTERM)
		select {
		case <-p.done:
		case <-time.After(5 * time.Second):
			cmd.Process.Kill()
			<-p.done
		}
		if t.Failed() {
			b, _ := os.ReadFile(logPath)
			t.Logf("%s:\n%s", filepath.Base(logPath), b)
		}
	})
	return p
}

func waitHealthy(t *testing.T, endpoint string, p *process) {
	t.Helper()
	client := &http.Client{Timeout: time.Second}
	deadline := time.Now().Add(20 * time.Second)
	for time.Now().Before(deadline) {
		select {
		case <-p.done:
			t.Fatalf("etcd exited before becoming healthy; see %s", p.log)
		default:
		}
		resp, err := client.Get(endpoint + "/health")
		if err == nil {
			b, _ := io.ReadAll(resp.Body)
			resp.Body.Close()
			if resp.StatusCode == 200 && strings.Contains(string(b), `"health":"true"`) {
				return
			}
		}
		time.Sleep(100 * time.Millisecond)
	}
	t.Fatalf("etcd did not become healthy at %s; see %s", endpoint, p.log)
}

func writeConfig(t *testing.T, path, name, data, listenPeer, peer, client, cluster, state string) {
	t.Helper()
	s := fmt.Sprintf(`name: %s
data-dir: %s
listen-peer-urls: %s
initial-advertise-peer-urls: %s
listen-client-urls: %s
advertise-client-urls: %s
initial-cluster: %s
initial-cluster-state: %s
initial-cluster-token: addon-startup-regression
`, name, data, listenPeer, peer, client, client, cluster, state)
	if err := os.WriteFile(path, []byte(s), 0600); err != nil {
		t.Fatal(err)
	}
}

func binary(t *testing.T, variable, fallback string) string {
	t.Helper()
	path := os.Getenv(variable)
	if path == "" {
		path = fallback
	}
	resolved, err := exec.LookPath(path)
	if err != nil {
		t.Fatalf("set %s to a local %s binary: %v", variable, fallback, err)
	}
	return resolved
}

func ctlResult(command, endpoint string, args ...string) (string, error) {
	ctx, cancel := context.WithTimeout(context.Background(), 8*time.Second)
	defer cancel()
	argv := append([]string{"--endpoints=" + endpoint, "--dial-timeout=2s", "--command-timeout=5s"}, args...)
	cmd := exec.CommandContext(ctx, command, argv...)
	// Keep developer etcdctl settings and the test's ETCDCTL_BINARY variable
	// from affecting RPCs or adding warnings to --print-value-only output.
	for _, item := range os.Environ() {
		if !strings.HasPrefix(item, "ETCDCTL_") {
			cmd.Env = append(cmd.Env, item)
		}
	}
	b, err := cmd.CombinedOutput()
	return string(b), err
}

func ctl(t *testing.T, command, endpoint string, args ...string) string {
	t.Helper()
	b, err := ctlResult(command, endpoint, args...)
	if err != nil {
		t.Fatalf("etcdctl %v: %v\n%s", args, err, b)
	}
	return b
}

func addMember(t *testing.T, command, endpoint, peer string) {
	t.Helper()
	// /health can succeed before the strict reconfiguration check's required
	// five seconds of continuous peer connectivity. Retry only that rejection.
	deadline := time.Now().Add(15 * time.Second)
	for {
		b, err := ctlResult(command, endpoint, "member", "add", "etcd-3", "--peer-urls="+peer)
		if err == nil {
			return
		}
		if !strings.Contains(b, "etcdserver: unhealthy cluster") || time.Now().After(deadline) {
			t.Fatalf("member add: %v\n%s", err, b)
		}
		time.Sleep(200 * time.Millisecond)
	}
}

func TestStartupMembership(t *testing.T) {
	etcd := binary(t, "ETCD_BINARY", "etcd")
	etcdctl := binary(t, "ETCDCTL_BINARY", "etcdctl")
	bash := binary(t, "BASH_BINARY", "bash")
	_, sourceFile, _, _ := runtime.Caller(0)
	scripts := filepath.Join(filepath.Dir(sourceFile), "../scripts")
	// Allows the identical integration regression to be run against a base ref.
	if override := os.Getenv("ETCD_SCRIPTS_DIR"); override != "" {
		scripts = override
	}
	for _, scenario := range []string{"stale_first_peer", "unavailable_first_peer"} {
		t.Run(scenario, func(t *testing.T) {
			dir := t.TempDir()
			peers := []*peerProxy{newPeerProxy(t), newPeerProxy(t), newPeerProxy(t)}
			sort.Slice(peers, func(i, j int) bool { return peers[i].server.URL < peers[j].server.URL })
			entries := make([]string, 3)
			for i, peer := range peers {
				entries[i] = fmt.Sprintf("etcd-%d=%s", i, peer.server.URL)
			}
			cluster := strings.Join(entries, ",")
			clients := make([]string, 3)
			processes := make([]*process, 3)
			for i, peer := range peers {
				clients[i] = loopbackURL(t)
				conf := filepath.Join(dir, fmt.Sprintf("etcd-%d.conf", i))
				writeConfig(t, conf, fmt.Sprintf("etcd-%d", i), filepath.Join(dir, fmt.Sprintf("data-%d", i)), peer.backend, peer.server.URL, clients[i], cluster, "new")
				processes[i] = startProcess(t, filepath.Join(dir, fmt.Sprintf("etcd-%d.log", i)), etcd, []string{"--config-file", conf}, os.Environ())
			}
			for i, client := range clients {
				waitHealthy(t, client, processes[i])
			}
			client := &http.Client{Timeout: 3 * time.Second}
			resp, err := client.Get(peers[0].server.URL + "/members")
			if err != nil {
				t.Fatal(err)
			}
			oldMembers, err := io.ReadAll(resp.Body)
			resp.Body.Close()
			if err != nil || resp.StatusCode != 200 {
				t.Fatalf("capture original membership: status=%d err=%v", resp.StatusCode, err)
			}
			joiningPeer, joiningClient := loopbackURL(t), loopbackURL(t)
			addMember(t, etcdctl, clients[0], joiningPeer)
			first := peers[0]
			first.mu.Lock()
			first.stale, first.clusterID = oldMembers, resp.Header.Get("X-Etcd-Cluster-ID")
			first.engineReads = 0
			if scenario == "stale_first_peer" {
				// Old code rotates to peer 1 after one stale read, then the
				// engine sees another stale response from peer 0 and exits.
				first.remaining = 2
			} else {
				first.unavailable = true
			}
			first.mu.Unlock()
			// Config order differs from URL order. The Pod list is deliberately
			// in the normal order; both routes must use the config's peer URLs.
			cluster = entries[2] + "," + entries[1] + "," + entries[0] + ",etcd-3=" + joiningPeer
			conf := filepath.Join(dir, "etcd-3.conf")
			data := filepath.Join(dir, "data-3")
			writeConfig(t, conf, "etcd-3", data, joiningPeer, joiningPeer, joiningClient, cluster, "existing")
			env := append(os.Environ(), "SCRIPTS_DIR="+scripts, "CONFIG_FILE_PATH="+conf, "DATA_DIR="+data,
				"CURRENT_POD_NAME=etcd-3", "ETCD_BINARY="+etcd,
				"PEER_FQDNS=etcd-0.fixture,etcd-1.fixture,etcd-2.fixture,etcd-3.fixture", "PEER_ENDPOINT=",
				"PEER_ZERO="+peers[0].server.URL, "PEER_ONE="+peers[1].server.URL, "PEER_TWO="+peers[2].server.URL)
			// Execute the real barrier followed by the same exec as start.sh.
			// The curl adapter is only needed to run old versions of the barrier,
			// which hardcode port 2380, against our ephemeral loopback ports.
			entry := `set -eo pipefail
. "$SCRIPTS_DIR/common.sh"
. "$SCRIPTS_DIR/peer-members.sh"
. "$SCRIPTS_DIR/startup-membership.sh"
default_conf="$CONFIG_FILE_PATH"
parse_config_value() { grep "^$1:" "$2" | cut -d: -f2- | xargs; }
curl() {
  local address="${@: -1}"
  case "$address" in
    http://etcd-0.fixture:2380/members) address="$PEER_ZERO/members";;
    http://etcd-1.fixture:2380/members) address="$PEER_ONE/members";;
    http://etcd-2.fixture:2380/members) address="$PEER_TWO/members";;
  esac
  command curl "${@:1:$#-1}" "$address"
}
wait_for_member_registration
exec "$ETCD_BINARY" --config-file "$default_conf"
`
			joining := startProcess(t, filepath.Join(dir, "etcd-3.log"), bash, []string{"-c", entry}, env)
			waitHealthy(t, joiningClient, joining)
			ctl(t, etcdctl, clients[1], "put", "/addon/startup-test", "registered")
			if value := ctl(t, etcdctl, joiningClient, "get", "/addon/startup-test", "--print-value-only"); value != "registered\n" {
				t.Fatalf("new member read back %q", value)
			}
			first.mu.Lock()
			defer first.mu.Unlock()
			if first.engineReads == 0 || first.engineStales != 0 {
				t.Fatalf("engine membership reads=%d, stale reads=%d", first.engineReads, first.engineStales)
			}
			if scenario == "stale_first_peer" && first.staleReads != 2 {
				t.Fatalf("barrier accepted before both stale observations: reads=%d", first.staleReads)
			}
			t.Logf("3 -> 4 members healthy; write/read passed; barrier stale reads=%d, engine stale reads=%d", first.staleReads, first.engineStales)
		})
	}
}
