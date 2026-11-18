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
echo " 6. Jinja2, Python, JSON, YAML, Precedence & Policy Validation"
echo "================================================================="
export TEST_INVENTORIES="${INVENTORIES[*]}"
export TEST_PLAYBOOKS="playbook.yml ${OPS_PLAYBOOKS[*]} ${PROV_PLAYBOOKS[*]}"
export TEST_FREEIPA="${FREEIPA_PLAYBOOKS[*]}"
python3 - <<'EOF'
import ast, glob, json, os, re, subprocess, sys
import jinja2, yaml

sys.dont_write_bytecode = True

errors = []
env = jinja2.Environment()

def load_yaml(path):
    with open(path, encoding="utf-8") as f:
        return yaml.safe_load(f) or {}

j2_files = sorted(glob.glob("**/*.j2", recursive=True))
for p in j2_files:
    with open(p, encoding="utf-8") as f:
        try:
            env.parse(f.read())
        except Exception as e:
            errors.append(f"Jinja2 parse error in {p}: {e}")
print(f"  [✓] Parsed {len(j2_files)} Jinja2 templates")

# Render all role templates with realistic cluster context & validate output
render_env = jinja2.Environment(trim_blocks=True)
render_env.filters["bool"] = lambda v: str(v).lower() in ("true", "1", "yes") if not isinstance(v, bool) else v
render_env.filters["to_json"] = json.dumps
render_env.filters["regex_replace"] = lambda v, pat, rep="": re.sub(pat, rep, str(v))
render_env.filters["difference"] = lambda a, b: [x for x in a if x not in b]

render_ctx = {}
for df in sorted(glob.glob("roles/*/defaults/main.yml")):
    render_ctx.update(load_yaml(df))
render_ctx.update(load_yaml("group_vars/all/admin_users.yml"))
render_ctx.update(load_yaml("group_vars/all/vault.example.yml"))
render_ctx.update({
    "domain_name": "example.com",
    "inventory_hostname": "proxy-01",
    "ansible_host": "203.0.113.10",
    "internal_ip": "10.0.1.10",
    "external_fqdn": "web1.example.com",
    "enable_internal_tls": True,
    "ansible_default_ipv4": {"interface": "eth0"},
    "group_names": ["webservers", "headless_nodes"],
    "alertmanager_slack_webhook_url": "https://hooks.slack.com/services/T00/B00/X00",
    "alertmanager_google_chat_webhook_url": "https://chat.googleapis.com/v1/spaces/AAA/messages",
    "alertmanager_teams_webhook_url": "https://outlook.office.com/webhook/xxx",
    "groups": {
        "proxies": ["proxy-01", "proxy-02"],
        "webservers": ["web-01", "web-02"],
        "monitoring": ["mon-01"],
        "teleport_servers": ["teleport-01"],
        "freeipa_servers": ["ipa-01"],
        "databases": ["db-01"],
        "redis_servers": ["redis-01"],
        "rabbitmq_servers": ["mq-01"],
        "headless_nodes": ["proxy-01", "proxy-02", "web-01", "web-02", "mon-01", "teleport-01"],
    },
    "hostvars": {
        "proxy-01": {"ansible_host": "203.0.113.10", "internal_ip": "10.0.1.10"},
        "proxy-02": {"ansible_host": "203.0.113.11", "internal_ip": "10.0.1.11"},
        "web-01": {"ansible_host": "10.0.2.10", "internal_ip": "10.0.2.10", "external_fqdn": "app.example.com"},
        "web-02": {"ansible_host": "10.0.2.11", "internal_ip": "10.0.2.11", "external_fqdn": "app.example.com"},
        "mon-01": {"ansible_host": "10.0.3.10", "internal_ip": "10.0.3.10", "monitoring_fqdn": "mon.example.com", "grafana_fqdn": "grafana.example.com"},
        "teleport-01": {"ansible_host": "10.0.4.10", "internal_ip": "10.0.4.10", "teleport_fqdn": "teleport.example.com"},
        "ipa-01": {"ansible_host": "10.0.5.10", "internal_ip": "10.0.5.10", "freeipa_fqdn": "ipa.example.com"},
        "db-01": {"ansible_host": "10.0.6.10", "internal_ip": "10.0.6.10"},
        "redis-01": {"ansible_host": "10.0.7.10", "internal_ip": "10.0.7.10"},
        "mq-01": {"ansible_host": "10.0.8.10", "internal_ip": "10.0.8.10", "rabbitmq_mgmt_fqdn": "mq.example.com"},
    },
})
for _ in range(2):
    for k, v in list(render_ctx.items()):
        if isinstance(v, str) and "{{" in v:
            out = render_env.from_string(v).render(**render_ctx)
            try:
                render_ctx[k] = ast.literal_eval(out)
            except Exception:
                render_ctx[k] = out

role_j2_files = sorted(glob.glob("roles/*/templates/*.j2"))
rendered_yaml_cnt = rendered_sh_cnt = rendered_py_cnt = 0
for tpl in role_j2_files:
    try:
        with open(tpl, encoding="utf-8") as f:
            rendered = render_env.from_string(f.read()).render(**render_ctx)
        if tpl.endswith((".yml.j2", ".yaml.j2")):
            list(yaml.safe_load_all(rendered))
            rendered_yaml_cnt += 1
        elif tpl.endswith(".sh.j2"):
            res = subprocess.run(["bash", "-n"], input=rendered, text=True, capture_output=True)
            if res.returncode != 0:
                errors.append(f"Rendered shell template bash -n error in {tpl}: {res.stderr.strip()}")
            rendered_sh_cnt += 1
        elif tpl.endswith(".py.j2"):
            ast.parse(rendered, filename=tpl)
            rendered_py_cnt += 1
        elif tpl.endswith("haproxy.cfg.j2"):
            for i, line in enumerate(rendered.splitlines(), 1):
                if line.strip().startswith("bind ") and "mode " in line:
                    errors.append(f"Concatenated bind/mode line in rendered {tpl}:{i}: {line}")
                if len(re.findall(r"\bserver\s+\S+", line)) > 1:
                    errors.append(f"Concatenated server lines in rendered {tpl}:{i}: {line}")
    except Exception as e:
        errors.append(f"Template render/validation error in {tpl}: {e}")
print(f"  [✓] Rendered {len(role_j2_files)} role templates ({rendered_yaml_cnt} YAML, {rendered_sh_cnt} Bash, {rendered_py_cnt} Python)")

py_files = sorted(glob.glob("**/*.py", recursive=True))
for p in py_files:
    with open(p, encoding="utf-8") as f:
        try:
            ast.parse(f.read(), filename=p)
        except Exception as e:
            errors.append(f"Python syntax error in {p}: {e}")
print(f"  [✓] Validated {len(py_files)} Python scripts")

json_files = sorted(glob.glob("**/*.json", recursive=True))
for p in json_files:
    with open(p, encoding="utf-8") as f:
        try:
            json.load(f)
        except Exception as e:
            errors.append(f"JSON parse error in {p}: {e}")
print(f"  [✓] Validated {len(json_files)} JSON files")

fqcn_re = re.compile(r"^([a-z0-9_]+\.[a-z0-9_]+)\.[a-z0-9_]+$")
used_collections = {}

def scan_task_collections(node, path):
    if isinstance(node, dict):
        is_task_block = any(k in node for k in ("name", "block", "rescue", "always", "when", "loop", "with_items", "notify", "register"))
        if is_task_block:
            for k in node:
                if isinstance(k, str):
                    m = fqcn_re.match(k)
                    if m and m.group(1) != "ansible.builtin":
                        used_collections.setdefault(m.group(1), set()).add(path)
        for v in node.values():
            scan_task_collections(v, path)
    elif isinstance(node, list):
        for item in node:
            scan_task_collections(item, path)

yml_files = sorted(set(
    glob.glob("**/*.yml", recursive=True)
    + glob.glob("**/*.yaml", recursive=True)
    + glob.glob(".github/**/*.yml", recursive=True)
))
for p in yml_files:
    with open(p, encoding="utf-8") as f:
        try:
            docs = list(yaml.safe_load_all(f))
            if not p.startswith((".github/", "group_vars/", "host_vars/", "vars/")):
                scan_task_collections(docs, p)
        except Exception as e:
            errors.append(f"YAML parse error in {p}: {e}")
print(f"  [✓] Validated {len(yml_files)} YAML files")

link_re = re.compile(r"\[[^\]]+\]\(([^)#]*)(#[^)]+)?\)")
math_re = re.compile(r"\$\$[^\$]+\$\$|(?<!\\)\$[^\$\n]+\$")
inline_code_re = re.compile(r"`[^`]+`")
mermaid_edge_re = re.compile(r"\|([^|\n]+)\|")
md_files = sorted(glob.glob("**/*.md", recursive=True))

def extract_md_headings(md_lines):
    headings = set()
    in_f = False
    fc = ""
    fl = 0
    for raw in md_lines:
        mo = re.match(r"^\s{0,3}(`{3,}|~{3,})(.*)$", raw)
        if not in_f and mo:
            in_f, fc, fl = True, mo.group(1)[0], len(mo.group(1))
            continue
        if in_f:
            if re.match(rf"^\s{{0,3}}{re.escape(fc)}{{{fl},}}\s*$", raw):
                in_f = False
            continue
        hm = re.match(r"^#{1,6}\s+(.+)$", raw)
        if hm:
            h = re.sub(r"[`*_~]", "", hm.group(1).strip().lower())
            h = re.sub(r"[^\w\s-]", "", h)
            headings.add(re.sub(r"\s+", "-", h))
    return headings

md_headings_cache = {}
for md in md_files:
    with open(md, encoding="utf-8") as f:
        md_headings_cache[md] = extract_md_headings(f.read().splitlines())

with open("README.md", encoding="utf-8") as f:
    readme_text = f.read()
for d in sorted(glob.glob("docs/*.md")):
    if d not in readme_text:
        errors.append(f"Documentation index gap: {d} is not linked in README.md")

checked_links = 0
for md in md_files:
    with open(md, encoding="utf-8") as f:
        content = f.read()
    lines = content.splitlines()
    for m in link_re.finditer(content):
        target = m.group(1).strip()
        anchor = (m.group(2) or "").strip()
        if target.startswith(("http://", "https://", "mailto:", "conversation://", "file://")):
            continue
        if not target and not anchor:
            continue
        checked_links += 1
        resolved = md if not target else os.path.normpath(os.path.join(os.path.dirname(md), target))
        if not os.path.exists(resolved):
            errors.append(f"Broken relative link in {md}: {target} -> {resolved}")
        elif anchor and resolved in md_headings_cache:
            if anchor[1:] not in md_headings_cache[resolved]:
                errors.append(f"Broken Markdown anchor in {md}: {target}{anchor}")

    in_fence = False
    fence_char = ""
    fence_len = 0
    in_mermaid = False
    mermaid_kind = ""
    for lineno, raw_line in enumerate(lines, 1):
        stripped = raw_line.strip()
        m_open = re.match(r"^\s{0,3}(`{3,}|~{3,})(.*)$", raw_line)
        if not in_fence and m_open:
            in_fence = True
            fence_char = m_open.group(1)[0]
            fence_len = len(m_open.group(1))
            in_mermaid = m_open.group(2).strip().lower().startswith("mermaid")
            mermaid_kind = ""
            continue
        if in_fence:
            m_close = re.match(rf"^\s{{0,3}}{re.escape(fence_char)}{{{fence_len},}}\s*$", raw_line)
            if m_close:
                in_fence = False
                in_mermaid = False
                mermaid_kind = ""
                continue
            if in_mermaid:
                if not mermaid_kind and stripped:
                    mermaid_kind = stripped.split()[0]
                if "<br" in stripped.lower():
                    errors.append(f"Mermaid HTML <br> tag in {md}:{lineno}: {stripped}")
                if mermaid_kind in ("flowchart", "graph"):
                    for em in mermaid_edge_re.finditer(raw_line):
                        label = em.group(1).strip()
                        if not (label.startswith('"') and label.endswith('"')):
                            errors.append(f"Unquoted Mermaid edge label {md}:{lineno}: |{label}|")
                    if not stripped.startswith("subgraph "):
                        no_edges = re.sub(r"\|[^|\n]+\|", "", raw_line)
                        for nm in re.finditer(r'([A-Za-z0-9_-]+)(\[|\{)([^\]\}\n]+)(\]|\})', no_edges):
                            inner = nm.group(3).strip()
                            if any(c in inner for c in " ():/") and not (inner.startswith('"') and inner.endswith('"')):
                                errors.append(f"Unquoted Mermaid node label in {md}:{lineno}: {nm.group(0)}")
                if re.search(r"--\s+[^>-]+\s+-->", raw_line):
                    errors.append(f"Unquoted Mermaid -- text --> edge syntax in {md}:{lineno}: {stripped}")
                if stripped.startswith("subgraph ") and not re.match(r'^subgraph\s+(?:[A-Za-z0-9_-]+(?:\s*\["[^"]+"\])?|"[^"]+")\s*$', stripped):
                    errors.append(f"Invalid Mermaid subgraph syntax in {md}:{lineno}: {stripped}")
            else:
                if any(ch in raw_line for ch in "┌┐┘▼▲") or "+---" in raw_line or re.search(r"└(?!── )", raw_line):
                    errors.append(f"Legacy ASCII flowchart in {md}:{lineno} (standardize on Mermaid or Markdown tables)")
            continue

        no_inline = inline_code_re.sub("", raw_line)
        for mm in math_re.finditer(no_inline):
            expr = mm.group(0)
            if r"\_" in expr or r"\%" in expr:
                errors.append(f"Escaped underscore/percent inside math block {md}:{lineno}: {expr}")

    if in_fence:
        errors.append(f"Unclosed fenced code block in {md}")

print(f"  [✓] Verified {checked_links} relative links and Markdown syntax across {len(md_files)} Markdown files")

vault_files = sorted(glob.glob("roles/**/*", recursive=True) + glob.glob("group_vars/**/*", recursive=True) + glob.glob("vars/**/*", recursive=True) + glob.glob("examples/**/*", recursive=True) + glob.glob("*.yml"))
vault_refs = set()
vault_re = re.compile(r"(?<![.\w])vault_[a-zA-Z0-9_]+")
for p in vault_files:
    if os.path.isdir(p) or p in ("group_vars/all/vault.example.yml", "group_vars/all/vault.yml"):
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
vault_actual_keys = None
if os.path.exists("group_vars/all/vault.yml"):
    with open("group_vars/all/vault.yml", encoding="utf-8") as f:
        vault_raw = f.read()
    if not vault_raw.startswith("$ANSIBLE_VAULT;"):
        vault_actual_keys = set((yaml.safe_load(vault_raw) or {}).keys())

used_vault_keys = {v for v, _ in vault_refs}
for v, p in sorted(vault_refs):
    if v not in vault_example_keys:
        errors.append(f"Vault SSOT mismatch: {v} (used in {p}) missing from group_vars/all/vault.example.yml")
    if vault_actual_keys is not None and v not in vault_actual_keys:
        errors.append(f"Vault SSOT mismatch: {v} (used in {p}) missing from group_vars/all/vault.yml")
for v in sorted(vault_example_keys - used_vault_keys):
    errors.append(f"Vault SSOT mismatch: {v} in group_vars/all/vault.example.yml is unused in code")

# Guard: required vault_* secrets must never use hardcoded literal defaults, must be documented in docs/security-vault.md, and group_vars/all/vault.yml must remain untracked
required_vault_secrets = (
    "vault_haproxy_stats_password", "vault_internal_ca_token", "vault_keepalived_auth_pass",
    "vault_grafana_admin_password", "vault_teleport_auth_token", "vault_freeipa_admin_password",
    "vault_freeipa_ds_password", "vault_db_password", "vault_db_replication_password",
    "vault_redis_password", "vault_rabbitmq_password", "vault_rabbitmq_admin_password",
    "vault_rabbitmq_erlang_cookie",
)
req_default_re = re.compile(rf"\b({'|'.join(required_vault_secrets)})\b[^}}\n]*\|\s*default\s*\(\s*['\"]")
for p in vault_files:
    if os.path.isdir(p) or p.endswith((".md", ".pyc")) or p in ("group_vars/all/vault.example.yml", "group_vars/all/vault.yml"):
        continue
    with open(p, encoding="utf-8", errors="ignore") as f:
        for lineno, line in enumerate(f, 1):
            code_part = line.split("#", 1)[0]
            if req_default_re.search(code_part):
                errors.append(f"Security policy violation in {p}:{lineno}: required vault secret has hardcoded default()")

with open("docs/security-vault.md", encoding="utf-8") as f:
    security_vault_doc = f.read()
for v in sorted(vault_example_keys):
    if v not in security_vault_doc:
        errors.append(f"Documentation gap: {v} missing from docs/security-vault.md")

tracked_vault = subprocess.run(["git", "ls-files", "--error-unmatch", "group_vars/all/vault.yml"], capture_output=True, text=True)
if tracked_vault.returncode == 0:
    errors.append("Security policy violation: group_vars/all/vault.yml must not be tracked in git")
print(f"  [✓] Verified {len(used_vault_keys)} vault_* SSOT references, docs coverage, and no-default-password guards")

# Detect unused variables in roles/*/defaults/main.yml
all_code_text = {}
for p in sorted(glob.glob("roles/**/*", recursive=True) + glob.glob("group_vars/**/*", recursive=True) + glob.glob("examples/**/*", recursive=True) + glob.glob("*.yml")):
    if os.path.isfile(p) and not p.endswith(".pyc"):
        with open(p, encoding="utf-8", errors="ignore") as f:
            all_code_text[p] = f.read()
default_var_cnt = 0
for df in sorted(glob.glob("roles/*/defaults/main.yml")):
    df_raw = all_code_text.get(df, "")
    df_data = yaml.safe_load(df_raw) or {}
    for k in df_data:
        default_var_cnt += 1
        used_elsewhere = any(re.search(rf"\b{re.escape(k)}\b", t) for p, t in all_code_text.items() if p != df)
        occ_self = len(re.findall(rf"\b{re.escape(k)}\b", df_raw))
        if not used_elsewhere and occ_self <= 1:
            errors.append(f"Unused role default variable in {df}: {k}")
print(f"  [✓] Verified all {default_var_cnt} role default variables are actively referenced")

# Verify playbook & inventory completeness against tests/run_tests.sh lists
tested_invs = set(os.environ.get("TEST_INVENTORIES", "").split())
tested_pbs = set(os.environ.get("TEST_PLAYBOOKS", "").split())
for pair in os.environ.get("TEST_FREEIPA", "").split():
    pb_p, inv_p = pair.split(":", 1)
    tested_pbs.add(pb_p)
    tested_invs.add(inv_p)

all_inis = set(glob.glob("**/*.ini", recursive=True))
for inv in sorted(all_inis - tested_invs):
    errors.append(f"Untested inventory file missing from tests/run_tests.sh: {inv}")

all_expected_pbs = set(glob.glob("*.yml"))
for p in glob.glob("examples/provisioning/*.yml"):
    if not os.path.basename(p).startswith("vars_"):
        all_expected_pbs.add(p)
for p in glob.glob("examples/freeipa/*freeipa*.yml"):
    all_expected_pbs.add(p)
for pb in sorted(all_expected_pbs - tested_pbs):
    errors.append(f"Untested playbook missing from tests/run_tests.sh: {pb}")
print(f"  [✓] Verified 100% coverage of {len(all_expected_pbs)} playbooks and {len(all_inis)} inventories")

# Verify staging vs production variable precedence via ansible-inventory
stg_res = subprocess.run(["ansible-inventory", "-i", "inventories/staging/hosts.ini", "--host", "proxy-stage-01"], capture_output=True, text=True)
prd_res = subprocess.run(["ansible-inventory", "-i", "inventories/production/hosts.ini", "--host", "proxy-prod-01"], capture_output=True, text=True)
if stg_res.returncode != 0:
    errors.append(f"ansible-inventory staging check failed: {stg_res.stderr.strip()}")
else:
    stg_vars = json.loads(stg_res.stdout)
    if stg_vars.get("acme_use_staging") is not True or stg_vars.get("prometheus_retention_time") != "7d":
        errors.append(f"Staging precedence mismatch on proxy-stage-01: acme_use_staging={stg_vars.get('acme_use_staging')}, prometheus_retention_time={stg_vars.get('prometheus_retention_time')}")
if prd_res.returncode != 0:
    errors.append(f"ansible-inventory production check failed: {prd_res.stderr.strip()}")
else:
    prd_vars = json.loads(prd_res.stdout)
    if prd_vars.get("domain_name") != "example.com":
        errors.append(f"Production precedence mismatch on proxy-prod-01: domain_name={prd_vars.get('domain_name')}")
print("  [✓] Verified multi-environment variable precedence (staging vs production)")

with open(".github/workflows/ci.yml", encoding="utf-8") as f:
    ci_content = f.read()
ci_collections = set()
for line in ci_content.splitlines():
    if "ansible-galaxy collection install" in line:
        parts = line.split("ansible-galaxy collection install", 1)[1].split()
        ci_collections.update(parts)

for col, paths in sorted(used_collections.items()):
    if col not in ci_collections:
        errors.append(f"CI collection mismatch: {col} (used in {', '.join(sorted(paths)[:3])}) missing from .github/workflows/ci.yml")
print(f"  [✓] Verified {len(used_collections)} Ansible collections match CI workflow")

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
