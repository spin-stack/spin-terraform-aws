// Package posture is the filters the fresh install's posture step (hack/fresh-install.sh posture)
// judges what AWS answers with. Each is run here on a recorded answer that keeps every promise,
// which must say nothing, and on the same answer with one value changed, which must say what broke:
// a filter that says nothing of anything passes the first half alone.
package posture

import (
	"bytes"
	"os"
	"os/exec"
	"strings"
	"testing"
)

// judge is what filter says of fixture once the jq program change has changed it. The test reads
// both itself, so that go test's cache knows a run after either changed is a new one.
func judge(t *testing.T, fixture, change, filter string, args ...string) string {
	t.Helper()
	answer := jq(t, read(t, "testdata/"+fixture), change)
	return strings.TrimSpace(string(jq(t, answer, string(read(t, filter)), append([]string{"-r"}, args...)...)))
}

func jq(t *testing.T, stdin []byte, program string, args ...string) []byte {
	t.Helper()
	cmd := exec.Command("jq", append(args, program)...)
	cmd.Stdin = bytes.NewReader(stdin)
	var stderr bytes.Buffer
	cmd.Stderr = &stderr
	out, err := cmd.Output()
	if err != nil {
		t.Fatalf("jq %s: %v: %s", program, err, stderr.String())
	}
	return out
}

func read(t *testing.T, path string) []byte {
	t.Helper()
	b, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	return b
}

func TestEachFilterSaysNothingOfAKeptPromiseAndNamesEachBrokenOne(t *testing.T) {
	const (
		i   = ".Reservations[0].Instances[1]"
		key = "arn:aws:kms:us-east-1:123456789012:key/00000000-0000-4000-8000-0000000d15c5"
		ips = `["198.51.100.10","198.51.100.11","10.0.1.10","10.0.1.11"]`
	)
	volumes := []string{"--arg", "key", key}
	trail := []string{"--argjson", "ips", ips}
	for _, c := range []struct {
		name, fixture, change, want, filter string
		args                                []string
	}{
		{"instances keep their promises", "instances.json", ".", "", "instances.jq", nil},
		{"IMDSv1", "instances.json", i + `.MetadataOptions.HttpTokens = "optional"`, "i-0aaaaaaaaaaaaaaa2: the metadata service answers IMDSv1", "instances.jq", nil},
		{"two hops", "instances.json", i + ".MetadataOptions.HttpPutResponseHopLimit = 2", "answers 2 hops away", "instances.jq", nil},
		{"IPv6", "instances.json", i + `.MetadataOptions.HttpProtocolIpv6 = "enabled"`, "answers on IPv6", "instances.jq", nil},
		{"tags", "instances.json", i + `.MetadataOptions.InstanceMetadataTags = "enabled"`, "says the instance's tags", "instances.jq", nil},
		{"legacy BIOS", "instances.json", i + `.CurrentInstanceBootMode = "legacy-bios"`, "boot mode legacy-bios", "instances.jq", nil},

		{"volumes encrypted", "volumes.json", ".", "", "volumes.jq", volumes},
		{"a volume in the clear", "volumes.json", ".Volumes[1].Encrypted = false", "vol-0aaaaaaaaaaaaaaa2 on i-0aaaaaaaaaaaaaaa2: not encrypted", "volumes.jq", volumes},
		{"a volume under aws/ebs", "volumes.json", `.Volumes[1].KmsKeyId = "arn:aws:kms:us-east-1:123456789012:key/00000000-0000-4000-8000-0000000ae0b5"`,
			"vol-0aaaaaaaaaaaaaaa2 on i-0aaaaaaaaaaaaaaa2: encrypted under arn:aws:kms:us-east-1:123456789012:key/00000000-0000-4000-8000-0000000ae0b5, not the installation's key", "volumes.jq", volumes},

		{"nothing denied is allowed", "denied.json", ".", "", "reach.jq", []string{"--arg", "want", "denied"}},
		{"a denied action allowed", "denied.json", `.EvaluationResults[0].EvalDecision = "allowed"`, "iam:CreateRole on *: allowed, want denied", "reach.jq", []string{"--arg", "want", "denied"}},
		{"everything allowed is allowed", "allowed.json", ".", "", "reach.jq", []string{"--arg", "want", "allowed"}},
		{"an allowed action denied", "allowed.json", `.EvaluationResults[0].EvalDecision = "implicitDeny"`, "logs:PutLogEvents", "reach.jq", []string{"--arg", "want", "allowed"}},

		{"the trail is the machines'", "trail.json", ".", "", "trail.jq", trail},
		{"a refused call", "trail.json", `.Events[0].CloudTrailEvent |= (fromjson | .errorCode = "AccessDenied" | tojson)`, "CreateLogStream was refused (AccessDenied)", "trail.jq", trail},
		{"a call from elsewhere", "trail.json", `.Events[1].CloudTrailEvent |= (fromjson | .sourceIPAddress = "203.0.113.9" | tojson)`, "GetCallerIdentity from 203.0.113.9", "trail.jq", trail},
	} {
		t.Run(c.name, func(t *testing.T) {
			got := judge(t, c.fixture, c.change, c.filter, c.args...)
			if c.want == "" && got != "" {
				t.Errorf("a recorded answer that keeps every promise was judged broken:\n%s", got)
			}
			if !strings.Contains(got, c.want) {
				t.Errorf("want a line with %q, got:\n%s", c.want, got)
			}
		})
	}
}
