// Command enroll adds an SSH key to the person a session is, confirmed with a passkey, as a person
// does once in the browser: the fresh install's smoke has nobody to touch a key, and spin certifies
// only a key added with a passkey's assertion. The passkey is made here, in memory, and registered
// as the person's first - which their session alone may do - so it is the installation's first
// administrator on an installation nobody else has signed in to, and it ends with this process.
//
// It is spin's passkeytest (internal/passkey/passkeytest) over the control plane's API as JSON:
// spin is private, so this repository cannot build what spin's e2e lane runs, and the authenticator
// needs only the standard library. A file with no module, so no toolchain or dependency is pinned:
//
//	go run hack/enroll/main.go -endpoint https://app.<domain> -token-file <file> -key <id_ed25519.pub>
package main

import (
	"bytes"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/sha256"
	"crypto/x509"
	"encoding/base64"
	"encoding/binary"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"net/http"
	"os"
	"strings"
	"time"
)

// name is what the passkey and the key are called in the person's list.
const name = "fresh-install"

func main() {
	endpoint := flag.String("endpoint", "", "the control plane, https://app.<domain>")
	// A file, never a flag: a session token on a command line is in ps.
	tokenFile := flag.String("token-file", "", "the file holding the person's session token")
	keyFile := flag.String("key", "", "the SSH public key to add, as ssh-keygen writes it")
	flag.Parse()
	if err := run(*endpoint, *tokenFile, *keyFile); err != nil {
		fmt.Fprintln(os.Stderr, "enroll:", err)
		os.Exit(1)
	}
}

func run(endpoint, tokenFile, keyFile string) error {
	if endpoint == "" || tokenFile == "" || keyFile == "" {
		return errors.New("-endpoint, -token-file and -key are all required")
	}
	token, err := os.ReadFile(tokenFile)
	if err != nil {
		return err
	}
	line, err := os.ReadFile(keyFile)
	if err != nil {
		return err
	}
	key, fingerprint, err := publicKey(string(line))
	if err != nil {
		return err
	}
	c := client{endpoint: strings.TrimRight(endpoint, "/"), token: strings.TrimSpace(string(token)),
		http: &http.Client{Timeout: 30 * time.Second}}

	reg, err := c.begin("PASSKEY_PURPOSE_REGISTER", "")
	if err != nil {
		return err
	}
	// Only a first passkey is registered with a session alone: one already there is somebody's
	// this process cannot assert with.
	if len(reg.CredentialIDs) > 0 {
		return fmt.Errorf("the person has %d passkeys already, and this one could only be their first", len(reg.CredentialIDs))
	}
	a, err := newAuthenticator(reg.RPID)
	if err != nil {
		return err
	}
	spki, err := x509.MarshalPKIXPublicKey(&a.key.PublicKey)
	if err != nil {
		return err
	}
	if err := c.call("spin.v1.PasskeyService/RegisterPasskey", map[string]any{
		"name": name, "challenge": reg.Challenge, "credentialId": a.id,
		"clientDataJson": a.clientData("webauthn.create", reg.Challenge), "authenticatorData": a.authenticatorData(),
		"publicKey": spki,
	}, nil); err != nil {
		return err
	}

	add, err := c.begin("PASSKEY_PURPOSE_ADD_SSH_KEY", fingerprint)
	if err != nil {
		return err
	}
	stepUp, err := a.assert(add.Challenge)
	if err != nil {
		return err
	}
	if err := c.call("spin.v1.SSHKeyService/AddSSHKey", map[string]any{
		"name": name, "publicKey": key, "stepUp": stepUp, "forSession": false,
	}, nil); err != nil {
		return err
	}
	fmt.Printf("added %s with a passkey registered for %s\n", fingerprint, reg.RPID)
	return nil
}

// publicKey is an authorized_keys line's type and key, without its comment, and the key's
// fingerprint as ssh-keygen -l prints it: what a step-up to add it names.
func publicKey(line string) (string, string, error) {
	fields := strings.Fields(line)
	if len(fields) < 2 {
		return "", "", errors.New("the key file holds no public key")
	}
	blob, err := base64.StdEncoding.DecodeString(fields[1])
	if err != nil {
		return "", "", fmt.Errorf("the key file's key: %w", err)
	}
	sum := sha256.Sum256(blob)
	return fields[0] + " " + fields[1], "SHA256:" + base64.RawStdEncoding.EncodeToString(sum[:]), nil
}

// client is the control plane's Connect API, as JSON, under the person's session.
type client struct {
	endpoint, token string
	http            *http.Client
}

// ceremony is what BeginPasskeyCeremony answers. Bytes are base64 in proto's JSON, which
// encoding/json reads into a []byte as it is.
type ceremony struct {
	Challenge     []byte   `json:"challenge"`
	RPID          string   `json:"rpId"`
	CredentialIDs [][]byte `json:"credentialIds"`
}

func (c client) begin(purpose, subject string) (ceremony, error) {
	var got ceremony
	err := c.call("spin.v1.PasskeyService/BeginPasskeyCeremony", map[string]any{"purpose": purpose, "subject": subject}, &got)
	if err == nil && (len(got.Challenge) == 0 || got.RPID == "") {
		err = fmt.Errorf("a %s ceremony began with no challenge or no relying party", purpose)
	}
	return got, err
}

func (c client) call(procedure string, req, resp any) error {
	body, err := json.Marshal(req)
	if err != nil {
		return err
	}
	r, err := http.NewRequest(http.MethodPost, c.endpoint+"/"+procedure, bytes.NewReader(body))
	if err != nil {
		return err
	}
	r.Header.Set("Content-Type", "application/json")
	r.Header.Set("Authorization", "Bearer "+c.token)
	res, err := c.http.Do(r)
	if err != nil {
		return fmt.Errorf("%s: %w", procedure, err)
	}
	defer res.Body.Close() //nolint:errcheck // read to the end below; a close error says nothing more
	out, err := io.ReadAll(res.Body)
	if err != nil {
		return fmt.Errorf("%s: %w", procedure, err)
	}
	if res.StatusCode != http.StatusOK {
		return fmt.Errorf("%s: %s: %s", procedure, res.Status, strings.TrimSpace(string(out)))
	}
	if resp == nil {
		return nil
	}
	return json.Unmarshal(out, resp)
}

// authenticator is one passkey, held in memory, answering as a browser's authenticator does: an
// ES256 key, user present and verified.
type authenticator struct {
	key     *ecdsa.PrivateKey
	id      []byte
	rpID    string
	counter uint32
}

func newAuthenticator(rpID string) (*authenticator, error) {
	key, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		return nil, err
	}
	id := make([]byte, 16)
	if _, err := rand.Read(id); err != nil {
		return nil, err
	}
	return &authenticator{key: key, id: id, rpID: rpID}, nil
}

// clientData is the page's: the dashboard's origin, which is a name under the relying party.
func (a *authenticator) clientData(ceremony string, challenge []byte) []byte {
	return fmt.Appendf(nil, `{"type":%q,"challenge":%q,"origin":%q,"crossOrigin":false}`,
		ceremony, base64.RawURLEncoding.EncodeToString(challenge), "https://app."+a.rpID)
}

// authenticatorData is the relying party's hash, the flags (user present 0x01, verified 0x04) and
// a counter that only goes up.
func (a *authenticator) authenticatorData() []byte {
	a.counter++
	rp := sha256.Sum256([]byte(a.rpID))
	d := make([]byte, 37)
	copy(d, rp[:])
	d[32] = 0x05
	binary.BigEndian.PutUint32(d[33:], a.counter)
	return d
}

// assert is the passkey's assertion over challenge, as spin's PasskeyAssertion carries it.
func (a *authenticator) assert(challenge []byte) (map[string]any, error) {
	client := a.clientData("webauthn.get", challenge)
	auth := a.authenticatorData()
	clientHash := sha256.Sum256(client)
	digest := sha256.Sum256(append(append([]byte{}, auth...), clientHash[:]...))
	sig, err := ecdsa.SignASN1(rand.Reader, a.key, digest[:])
	if err != nil {
		return nil, err
	}
	return map[string]any{
		"challenge": challenge, "credentialId": a.id, "clientDataJson": client,
		"authenticatorData": auth, "signature": sig,
	}, nil
}
