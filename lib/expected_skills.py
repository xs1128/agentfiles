"""Every managed skill name an agent's skills dir should hold.

Shared so doctor.sh (what is missing) and lib/skills.sh (what is now stale)
can never disagree about the set. Extra argv entries are agent-specific
additions, e.g. claude's workflow.md.
"""

import json
import os
import sys

skills_m, wiki_m, repo, dest, *extra = sys.argv[1:]
names = set(json.load(open(skills_m))["skills"]) | set(extra)
wiki = json.load(open(wiki_m))
if dest in [os.path.expanduser(p) for p in wiki["linkInto"]]:
    names |= set(wiki["skills"])
shared = os.path.join(repo, "shared", "skills")
names |= {n for n in os.listdir(shared) if os.path.isdir(os.path.join(shared, n))}
print("\n".join(sorted(names)))
