#!/usr/bin/env bash
# ==============================================================================
# Script: run_tests.sh
# Purpose: Execute local verification, syntax validation, and linting
# ==============================================================================
set -euo pipefail

echo "================================================================="
echo " 1. Shell Script Syntax Validation (bash -n)"
echo "================================================================="
find . -name "*.sh" -not -path "*/.git/*" -print0 | while IFS= read -r -d '' file; do
  bash -n "$file"
  echo "  [✓] $file"
done

echo ""
echo "================================================================="
echo " 2. Main Playbook Syntax Checks Across All Inventories"
echo "================================================================="
INVENTORIES=(
  "inventory.ini"
  "inventories/staging/hosts.ini"
  "inventories/production/hosts.ini"
  "examples/inventories/inventory.aws.ini"
  "examples/inventories/inventory.gcp.ini"
  "examples/inventories/inventory.azure.ini"
  "examples/inventories/inventory.oci.ini"
  "examples/inventories/inventory.openstack.ini"
  "examples/inventories/inventory.freeipa.ini"
  "examples/topologies/scenario-1-unique-clients/inventory.ini"
  "examples/topologies/scenario-2-pooled-webservers/inventory.ini"
  "examples/topologies/scenario-3-hybrid/inventory.ini"
)

for inv in "${INVENTORIES[@]}"; do
  echo "  -> Checking playbook.yml with $inv..."
  ansible-playbook -i "$inv" playbook.yml --syntax-check > /dev/null
  echo "     [✓] PASS"
done

echo ""
echo "================================================================="
echo " 3. Operational Playbook Syntax Checks (Backup, Restore, Verify)"
echo "================================================================="
OPS_PLAYBOOKS=(
  "backup_cluster.yml"
  "restore_cluster.yml"
  "verify_cluster.yml"
  "rolling_maintenance.yml"
  "chaos_drill.yml"
)

for op in "${OPS_PLAYBOOKS[@]}"; do
  echo "  -> Checking $op..."
  ansible-playbook -i inventory.ini "$op" --syntax-check > /dev/null
  echo "     [✓] PASS"
done

echo ""
echo "================================================================="
echo " 4. Cloud Provisioning Playbook Syntax Checks"
echo "================================================================="
PROV_PLAYBOOKS=(
  "examples/provisioning/provision_aws.yml"
  "examples/provisioning/deprovision_aws.yml"
  "examples/provisioning/provision_aws_rds_postgresql.yml"
  "examples/provisioning/provision_aws_elasticache_redis.yml"
  "examples/provisioning/provision_aws_amazon_mq.yml"
  "examples/provisioning/provision_gcp.yml"
  "examples/provisioning/deprovision_gcp.yml"
  "examples/provisioning/provision_gcp_cloudsql_postgresql.yml"
  "examples/provisioning/provision_gcp_memorystore_redis.yml"
  "examples/provisioning/provision_azure.yml"
  "examples/provisioning/deprovision_azure.yml"
  "examples/provisioning/provision_azure_postgresql.yml"
  "examples/provisioning/provision_azure_cache_redis.yml"
  "examples/provisioning/provision_oci.yml"
  "examples/provisioning/deprovision_oci.yml"
  "examples/provisioning/provision_openstack.yml"
  "examples/provisioning/deprovision_openstack.yml"
)

for pb in "${PROV_PLAYBOOKS[@]}"; do
  echo "  -> Checking $pb..."
  ansible-playbook "$pb" --syntax-check > /dev/null
  echo "     [✓] PASS"
done

echo ""
echo "================================================================="
echo " 5. FreeIPA Example Playbook Syntax Checks"
echo "================================================================="
FREEIPA_PLAYBOOKS=(
  "examples/freeipa/standup_freeipa_cluster.yml:examples/freeipa/inventory.standup.ini"
  "examples/freeipa/enroll_existing_freeipa.yml:examples/freeipa/inventory.existing.ini"
)

for pair in "${FREEIPA_PLAYBOOKS[@]}"; do
  pb="${pair%%:*}"
  inv="${pair##*:}"
  echo "  -> Checking $pb with $inv..."
  ansible-playbook -i "$inv" "$pb" --syntax-check > /dev/null
  echo "     [✓] PASS"
done

echo ""
echo "================================================================="
echo " 6. Jinja2, Python, JSON, YAML & Markdown Link Validation"
echo "================================================================="
python3 - <<'EOF'
import glob, json, os, py_compile, re, sys
import jinja2, yaml

errors = []
env = jinja2.Environment()

j2_files = sorted(glob.glob("**/*.j2", recursive=True))
for p in j2_files:
    with open(p, encoding="utf-8") as f:
        try:
            env.parse(f.read())
        except Exception as e:
            errors.append(f"Jinja2 parse error in {p}: {e}")
print(f"  [✓] Parsed {len(j2_files)} Jinja2 templates")

py_files = sorted(glob.glob("**/*.py", recursive=True))
for p in py_files:
    try:
        py_compile.compile(p, doraise=True)
    except Exception as e:
        errors.append(f"Python compile error in {p}: {e}")
print(f"  [✓] Compiled {len(py_files)} Python scripts")

json_files = sorted(glob.glob("**/*.json", recursive=True))
for p in json_files:
    with open(p, encoding="utf-8") as f:
        try:
            json.load(f)
        except Exception as e:
            errors.append(f"JSON parse error in {p}: {e}")
print(f"  [✓] Validated {len(json_files)} JSON files")

yml_files = sorted(set(
    glob.glob("**/*.yml", recursive=True)
    + glob.glob("**/*.yaml", recursive=True)
    + glob.glob(".github/**/*.yml", recursive=True)
))
for p in yml_files:
    with open(p, encoding="utf-8") as f:
        try:
            list(yaml.safe_load_all(f))
        except Exception as e:
            errors.append(f"YAML parse error in {p}: {e}")
print(f"  [✓] Validated {len(yml_files)} YAML files")

link_re = re.compile(r"\[[^\]]+\]\(([^)#]*)(?:#[^)]*)?\)")
math_re = re.compile(r"\$\$[^\$]+\$\$|(?<!\\)\$[^\$\n]+\$")
inline_code_re = re.compile(r"`[^`]+`")
mermaid_edge_re = re.compile(r"\|([^|\n]+)\|")
md_files = sorted(glob.glob("**/*.md", recursive=True))
checked_links = 0
for md in md_files:
    with open(md, encoding="utf-8") as f:
        content = f.read()
    lines = content.splitlines()
    for m in link_re.finditer(content):
        target = m.group(1).strip()
        if not target or target.startswith(("http://", "https://", "mailto:", "conversation://", "file://")):
            continue
        checked_links += 1
        resolved = os.path.normpath(os.path.join(os.path.dirname(md), target))
        if not os.path.exists(resolved):
            errors.append(f"Broken relative link in {md}: {target} -> {resolved}")

    in_fence = False
    fence_char = ""
    fence_len = 0
    in_mermaid = False
    for lineno, raw_line in enumerate(lines, 1):
        stripped = raw_line.strip()
        m_open = re.match(r"^\s{0,3}(`{3,}|~{3,})(.*)$", raw_line)
        if not in_fence and m_open:
            in_fence = True
            fence_char = m_open.group(1)[0]
            fence_len = len(m_open.group(1))
            in_mermaid = m_open.group(2).strip().lower().startswith("mermaid")
            continue
        if in_fence:
            m_close = re.match(rf"^\s{{0,3}}{re.escape(fence_char)}{{{fence_len},}}\s*$", raw_line)
            if m_close:
                in_fence = False
                in_mermaid = False
                continue
            if in_mermaid:
                if "<br" in stripped.lower():
                    errors.append(f"Mermaid HTML <br> tag in {md}:{lineno}: {stripped}")
                if re.search(r"-->|--\|", raw_line):
                    for em in mermaid_edge_re.finditer(raw_line):
                        label = em.group(1).strip()
                        if ("(" in label or ")" in label) and not (label.startswith('"') and label.endswith('"')):
                            errors.append(f"Unquoted parentheses in Mermaid edge label {md}:{lineno}: |{label}|")
                if re.search(r"--\s+[^>-]+\s+-->", raw_line):
                    errors.append(f"Unquoted Mermaid -- text --> edge syntax in {md}:{lineno}: {stripped}")
                if stripped.startswith("subgraph ") and not re.match(r'^subgraph\s+(?:[A-Za-z0-9_-]+(?:\s*\["[^"]+"\])?|"[^"]+")\s*$', stripped):
                    errors.append(f"Invalid Mermaid subgraph syntax in {md}:{lineno}: {stripped}")
            continue

        no_inline = inline_code_re.sub("", raw_line)
        for mm in math_re.finditer(no_inline):
            expr = mm.group(0)
            if r"\_" in expr or r"\%" in expr:
                errors.append(f"Escaped underscore/percent inside math block {md}:{lineno}: {expr}")

    if in_fence:
        errors.append(f"Unclosed fenced code block in {md}")

print(f"  [✓] Verified {checked_links} relative links and Markdown syntax across {len(md_files)} Markdown files")

vault_files = sorted(glob.glob("roles/**/*", recursive=True) + glob.glob("group_vars/**/*", recursive=True) + glob.glob("*.yml"))
vault_refs = set()
vault_re = re.compile(r"(?<![.\w])vault_[a-zA-Z0-9_]+")
for p in vault_files:
    if os.path.isdir(p):
        continue
    with open(p, encoding="utf-8", errors="ignore") as f:
        for line in f:
            code_part = line.split("#", 1)[0]
            for m in vault_re.finditer(code_part):
                v = m.group(0)
                if v != "vault_password_file":
                    vault_refs.add((v, p))

with open("group_vars/all/vault.example.yml", encoding="utf-8") as f:
    vault_example_keys = set((yaml.safe_load(f) or {}).keys())
with open("group_vars/all/vault.yml", encoding="utf-8") as f:
    vault_raw = f.read()
vault_actual_keys = set((yaml.safe_load(vault_raw) or {}).keys()) if not vault_raw.startswith("$ANSIBLE_VAULT;") else None

for v, p in sorted(vault_refs):
    if v not in vault_example_keys:
        errors.append(f"Vault SSOT mismatch: {v} (used in {p}) missing from group_vars/all/vault.example.yml")
    if vault_actual_keys is not None and v not in vault_actual_keys:
        errors.append(f"Vault SSOT mismatch: {v} (used in {p}) missing from group_vars/all/vault.yml")
print(f"  [✓] Verified {len({v for v, _ in vault_refs})} vault_* references match SSOT vault files")

expected_groups = [
    "[proxies]", "[webservers]", "[monitoring]", "[teleport_servers]",
    "[freeipa_servers]", "[databases]", "[redis_servers]", "[rabbitmq_servers]",
    "[headless_nodes:children]",
]
inv_files = sorted(set(
    glob.glob("**/*.ini", recursive=True)
    + glob.glob("examples/provisioning/inventory_*.ini.j2")
))
for inv in inv_files:
    with open(inv, encoding="utf-8") as f:
        inv_content = f.read()
    missing_groups = [g for g in expected_groups if g not in inv_content]
    if missing_groups:
        errors.append(f"Inventory group parity mismatch in {inv}: missing {missing_groups}")
print(f"  [✓] Verified host group parity across {len(inv_files)} inventory files and templates")

if errors:
    for err in errors:
        print(f"  [✗] {err}", file=sys.stderr)
    sys.exit(1)
EOF

echo ""
echo "================================================================="
echo " All syntax and script validation checks PASSED successfully!"
echo "================================================================="
