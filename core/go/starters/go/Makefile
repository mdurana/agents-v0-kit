.PHONY: test verify

test:
	go test ./...

verify:
	rm -f cve-report.json
	go test ./... -coverprofile=coverage.out -json > go-test.json
	go run golang.org/x/vuln/cmd/govulncheck@latest -json ./... > govulncheck.json; status=$$?; \
	if [ $$status -ne 0 ] && [ $$status -ne 3 ]; then exit $$status; fi; \
	python3 -c 'import json,sys; src,dest=sys.argv[1:]; deps={};\
exec("for line in open(src,encoding=\"utf-8\"):\n line=line.strip()\n if not line:\n  continue\n msg=json.loads(line)\n finding=msg.get(\"finding\")\n if not isinstance(finding, dict):\n  continue\n trace=finding.get(\"trace\") or []\n module=\"?\"\n if trace and isinstance(trace[0], dict):\n  module=str(trace[0].get(\"module\") or \"?\")\n deps.setdefault(module, []).append({\"name\": str(finding.get(\"osv\") or \"?\"), \"severity\": \"HIGH\"})\n");\
open(dest,"w",encoding="utf-8").write(json.dumps({"dependencies":[{"fileName":name,"vulnerabilities":vulns} for name,vulns in sorted(deps.items())]})+"\n")' govulncheck.json cve-report.json || exit $$?; \
	if [ $$status -ne 0 ]; then exit $$status; fi
