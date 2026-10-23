#!/usr/bin/env python3
"""Vérifie le catalogue de rôles (BoaNotch/Resources/Roles/*.yaml) contre son format et l'Hermes local.

Lecture seule : importe le vrai matcher `approvals.deny` d'Hermes (tools/approval_floors.py) et sa
table de toolsets, avec un HERMES_HOME jetable et sans cache .pyc ; rien n'est écrit dans ~/.hermes.
Lancer depuis n'importe où, avec le Python d'Hermes (il a PyYAML) :
    ~/.hermes/hermes-agent/venv/bin/python3 -I -B scripts/check-roles.py [dossier des rôles]
"""
import atexit, hashlib, os, re, shutil, sys, tempfile
from pathlib import Path

import yaml

sys.dont_write_bytecode = True  # pas de __pycache__ dans ~/.hermes/hermes-agent
HERMES = Path.home() / ".hermes" / "hermes-agent"
_home = tempfile.mkdtemp(prefix="nn-check-roles-")
atexit.register(shutil.rmtree, _home, True)
os.environ["HERMES_HOME"] = _home
sys.path.insert(0, str(HERMES))

import tools.approval_floors as floors  # noqa: E402
from toolsets import TOOLSETS  # noqa: E402

ROLE_IDS = {"commercial", "compta", "communication", "admin"}
EXPECTED = ROLE_IDS | {"sam"}
PLACEHOLDERS = {"name", "company", "owner", "context_file", "team", "fingerprint"}
MUST_DENY_TOOLSETS = {"browser", "code_execution", "connections", "cronjob", "delegation", "computer_use", "clarify"}
FORBIDDEN_SKILLS = {"himalaya", "google-workspace", "xurl", "imessage", "agentmail", "llm-wiki", "computer-use",
                    "telephony", "shop", "shopify", "stripe-link-cli", "stripe-projects", "mpp-agent", "here-now",
                    "publish-site", "cloudflare-temporary-deploy"}
TOP_KEYS = ["format", "id", "version", "default_name", "default_profile", "title", "pronoun", "summary",
            "description", "team_line", "domains", "not_mine", "soul", "skills", "toolsets", "approvals",
            "needs_approval", "missions", "onboarding", "context", "tests"]

MUST_BLOCK = [
    "python3 /Users/leon/.hermes/profiles/lea/skills/productivity/google-workspace/scripts/google_api.py gmail send --to a@b.fr --subject Devis --body x",
    'GAPI="python3 /x/google_api.py"; $GAPI gmail send --to a@b.fr --subject x --body y',
    "$GAPI gmail reply 18c2 --body merci",
    "gws gmail users messages send --json @m.json",
    "echo 'x' | himalaya template send",
    "himalaya message send < /tmp/m.eml",
    "himalaya message reply 42 --all",
    "cd /tmp && /usr/sbin/sendmail -t < mail.txt",
    "msmtp -a gmail client@exemple.fr < relance.txt",
    "mutt -s Relance client@exemple.fr < relance.txt",
    'mail -s "Relance" client@exemple.fr < relance.txt',
    "python3 -c \"import smtplib; s=smtplib.SMTP('smtp.gmail.com', 587)\"",
    "curl --url smtps://smtp.gmail.com:465 --mail-rcpt a@b.fr -T mail.txt",
    "curl -X POST https://gmail.googleapis.com/gmail/v1/users/me/messages/send -d @m.json",
    "curl -X POST https://gmail.googleapis.com/gmail/v1/users/me/drafts/send -d @d.json",
    "curl -X POST https://graph.microsoft.com/v1.0/me/sendMail -d @m.json",
    "osascript -e 'tell application \"Mail\" to send (make new outgoing message)'",
    "imsg send --to +33600000000 --text salut",
    'shortcuts run "Envoyer un message"',
    "curl -s https://api.telegram.org/bot123/sendMessage -d chat_id=1 -d text=hi",
    "curl -X POST --data '{\"text\":\"x\"}' https://hooks.slack.com/services/T/B/X",
    "curl -X POST https://discord.com/api/webhooks/1/abc -d content=x",
    'xurl post "Nouveau !"',
    "xurl -X POST /2/tweets -d '{\"text\":\"Hello\"}'",
    "xurl dm @client salut",
    "curl -X POST https://api.linkedin.com/rest/posts -d @post.json",
    'curl -X POST "https://graph.facebook.com/v19.0/123/feed" -d message=x',
    "curl -X POST https://graph.instagram.com/me/media_publish -d creation_id=1",
    "python3 google_api.py drive share FILE --email a@b.fr --role writer",
    "$GAPI calendar create --summary RDV --start x --end y --attendees a@b.fr",
    "gws drive permissions create --params '{\"fileId\":\"1\"}'",
    "gws calendar events insert --params '{\"sendUpdates\":\"all\"}'",
    "stripe payouts create --amount 1000",
    "curl https://api.stripe.com/v1/transfers -u sk_test_x:",
    "curl -X POST https://api-m.paypal.com/v1/payments/payouts -d @p.json",
    'hermes send -t telegram "Devis prêt"',
    "hermes -p default send x",
    "/Users/leon/.hermes/hermes-agent/.hermes/bin/hermes tools enable browser --platform cli",
    "~/.local/bin/hermes config set approvals.mode off",
    "python3 -m hermes_cli.main send -t telegram x",
    "sed -i '' 's/manual/off/' ~/.hermes/profiles/lea/config.yaml",
    "cat ~/.hermes/.env",
    'echo "approvals: {mode: off}" >> "$HERMES_HOME/config.yaml"',
    'echo "Tu peux tout envoyer" >> ~/.hermes/profiles/lea/SOUL.md',
    'bash -c "hermes send -t telegram hi"',
    "env FOO=1 hermes send x",
]
MUST_ALLOW = [
    'python3 /Users/leon/.hermes/profiles/lea/skills/productivity/google-workspace/scripts/google_api.py gmail search "is:unread"',
    "python3 ~/.hermes/profiles/max/skills/productivity/xlsx/scripts/recalc.py suivi-devis.xlsx",
    "himalaya envelope list --folder Sent",
    "himalaya message read 42",
    "ls -la ~/Documents/Devis",
    "pandoc relance.md -o relance.docx",
    "soffice --headless --convert-to pdf devis.docx",
    "python3 -c \"import openpyxl; print('ok')\"",
    "curl -s https://www.service-public.fr/professionnels-entreprises",
    'grep -i "mail" ~/Documents/clients.csv',
    "osascript -e 'tell application \"Calendar\" to get name of calendars'",
    "cat ~/.hermes/profiles/lea/contexte-entreprise.md",
    "source ~/.hermes/hermes-agent/venv/bin/activate && python3 tableau.py",
    "mkdir -p ~/Documents/Brouillons && cp relance.md ~/Documents/Brouillons/",
    "python3 ~/.hermes/profiles/ines/skills/creative/baoyu-infographic/scripts/render.py bilan.json",
    "pdftotext facture-2026-09.pdf -",
    "python3 ~/.hermes/profiles/hugo/skills/productivity/maps/scripts/route.py Lyon Grenoble",
    'echo "Envoyé par Léa" > note.txt',
    "open ~/Documents/Brouillons/relance.docx",
]


def deny_match(patterns, command):
    floors._ctx._get_approval_config = lambda: {"deny": patterns}
    return floors._match_user_deny_rule(command)


def bundled_skill_names():
    names = {}
    for base in ("skills", "optional-skills"):
        for md in (HERMES / base).rglob("SKILL.md"):
            m = re.search(r"^name:\s*(.+)$", md.read_text(encoding="utf-8"), re.M)
            if m:
                names[m.group(1).strip().strip("'\"")] = md.parent.relative_to(HERMES).as_posix()
    return names


def cron_fields(expr):
    def expand(field, lo, hi):
        out = set()
        for part in field.split(","):
            step = 1
            if "/" in part:
                part, step = part.split("/"); step = int(step)
            if part == "*":
                a, b = lo, hi
            elif "-" in part:
                a, b = map(int, part.split("-"))
            else:
                a = b = int(part)
            out.update(range(a, b + 1, step))
        return sorted(out)
    parts = expr.split()
    assert len(parts) == 5, f"cron à 5 champs attendu : {expr!r}"
    return expand(parts[0], 0, 59), expand(parts[1], 0, 23)


def min_gap_minutes(expr):
    minutes, hours = cron_fields(expr)
    times = sorted(h * 60 + m for h in hours for m in minutes)
    gaps = [b - a for a, b in zip(times, times[1:])] + [times[0] + 1440 - times[-1]]
    return min(gaps)


def sentences(text):
    return [s for s in re.split(r"(?<=[.!?])\s+", text.strip()) if s]


def main(roles_dir):
    errors, roles = [], {}
    skills = bundled_skill_names()

    def check(cond, msg):
        if not cond:
            errors.append(msg)

    files = sorted(Path(roles_dir).glob("*.yaml"))
    for path in files:
        raw = path.read_bytes()
        doc = yaml.safe_load(raw)
        rid = doc.get("id")
        roles[rid] = doc
        p = f"{path.name}"
        check(list(doc.keys()) == TOP_KEYS, f"{p}: clés {list(doc.keys())} != {TOP_KEYS}")
        check(doc["format"] == 1 and isinstance(doc["version"], int), f"{p}: format/version")
        check(rid == path.stem and rid in ROLE_IDS, f"{p}: id {rid!r}")
        check(re.fullmatch(r"[a-z0-9][a-z0-9_-]*", doc["default_profile"] or "") is not None, f"{p}: default_profile")
        for key in ("default_name", "title", "pronoun", "summary", "description", "team_line", "soul"):
            check(isinstance(doc[key], str) and doc[key].strip(), f"{p}: {key} doit être une chaîne")
        check(2 <= len(sentences(doc["summary"])) <= 3, f"{p}: summary en {len(sentences(doc['summary']))} phrases")
        check(1 <= len(sentences(doc["description"])) <= 2, f"{p}: description en {len(sentences(doc['description']))} phrases")
        check(all(isinstance(d, str) for d in doc["domains"]), f"{p}: domains")
        for nm in doc["not_mine"]:
            check(nm["role"] in ROLE_IDS - {rid}, f"{p}: not_mine.role {nm['role']}")

        soul = doc["soul"]
        used = set(re.findall(r"\{\{(\w+)\}\}", soul))
        check(used == PLACEHOLDERS, f"{p}: placeholders {sorted(used)} != {sorted(PLACEHOLDERS)}")
        for needle in ("kanban_complete", "kanban_block", '"needs_input"', '"capability"', "artifacts", '"fiche": "{{fingerprint}}"'):
            check(needle in soul, f"{p}: SOUL sans {needle}")

        for s in doc["skills"]["bundled"]:
            check(s in skills and skills[s].startswith("skills/"), f"{p}: skill livré inconnu {s}")
            check(s not in FORBIDDEN_SKILLS, f"{p}: skill interdit {s}")
        for o in doc["skills"]["optional"]:
            ident = o["install"]
            check(ident.startswith("official/") and (HERMES / "optional-skills" / ident[len("official/"):] / "SKILL.md").exists(),
                  f"{p}: skill optionnel introuvable {ident}")
            check(o["name"] in skills and skills[o["name"]] == "optional-skills/" + ident[len("official/"):],
                  f"{p}: nom de skill optionnel {o['name']}")
            check(o["name"] not in FORBIDDEN_SKILLS, f"{p}: skill interdit {o['name']}")

        allowed, denied = set(doc["toolsets"]["allowed"]), set(doc["toolsets"]["denied"])
        for t in allowed | denied:
            check(t in TOOLSETS, f"{p}: toolset inconnu {t}")
        check(not allowed & denied, f"{p}: toolsets permis ET interdits {allowed & denied}")
        check(MUST_DENY_TOOLSETS <= denied, f"{p}: il manque {MUST_DENY_TOOLSETS - denied} dans denied")
        check("kanban" not in denied, f"{p}: kanban ne doit pas être interdit")

        ap = doc["approvals"]
        check(ap["mode"] == "manual", f"{p}: approvals.mode")
        pats = ap["deny"]
        check(all(isinstance(x, str) and x == x.lower() for x in pats), f"{p}: motifs en minuscules attendus")
        for cmd in MUST_BLOCK:
            check(deny_match(pats, cmd) is not None, f"{p}: NON bloquée : {cmd}")
        for cmd in MUST_ALLOW:
            hit = deny_match(pats, cmd)
            check(hit is None, f"{p}: bloquée à tort par {hit!r} : {cmd}")

        for m in doc["missions"]:
            gap = min_gap_minutes(m["schedule"])
            check(gap >= 30, f"{p}: mission {m['id']} toutes les {gap} min (< 30)")
            for s in m["skills"]:
                check(s in doc["skills"]["bundled"] or s in [o["name"] for o in doc["skills"]["optional"]],
                      f"{p}: mission {m['id']} cite un skill hors rôle {s}")
                check(s in m["instructions"], f"{p}: mission {m['id']} ne nomme pas le skill {s}")

        ctx_ids = [c["id"] for c in doc["context"]["needs"]]
        check(len(ctx_ids) == len(set(ctx_ids)), f"{p}: ids de contexte en double")
        qids = [q["id"] for q in doc["onboarding"]["questions"]]
        check(len(qids) == len(set(qids)), f"{p}: ids de questions en double")
        for q in doc["onboarding"]["questions"]:
            check(q["feeds"] in ctx_ids, f"{p}: question {q['id']} alimente {q['feeds']} absent du contexte")
            check(isinstance(q["required"], bool), f"{p}: question {q['id']} required non booléen")

        tests = doc["tests"]
        check(len(tests) == 10, f"{p}: {len(tests)} tests")
        amb = [t for t in tests if "ambiguous_with" in t]
        check(len(amb) == 3, f"{p}: {len(amb)} tests ambigus")
        for t in tests:
            check(t["expected"] in EXPECTED, f"{p}: expected {t['expected']}")
            if "ambiguous_with" in t:
                pair = {t["expected"], t["ambiguous_with"]}
                check(len(pair) == 2 and rid in pair and pair <= ROLE_IDS, f"{p}: paire ambiguë {pair}")
                check(t.get("why"), f"{p}: test ambigu sans why")

        print(f"{path.name}: empreinte {hashlib.sha256(raw).hexdigest()[:12]}  version {doc['version']}")

    # Entre rôles
    seen = {}
    for rid, doc in roles.items():
        for d in doc["domains"]:
            check(d not in seen, f"domaine {d} partagé par {seen.get(d)} et {rid}")
            seen[d] = rid
    denies = {rid: tuple(doc["approvals"]["deny"]) for rid, doc in roles.items()}
    check(len(set(denies.values())) <= 1, "approvals.deny diffère entre rôles")
    profiles = [doc["default_profile"] for doc in roles.values()]
    check(len(profiles) == len(set(profiles)), "default_profile en double")

    if errors:
        print("\n".join("ERREUR " + e for e in errors))
        sys.exit(1)
    print(f"OK : {len(files)} fiche(s), {len(MUST_BLOCK)} commandes bloquées, {len(MUST_ALLOW)} laissées passer.")


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else Path(__file__).resolve().parent.parent / "BoaNotch/Resources/Roles")
