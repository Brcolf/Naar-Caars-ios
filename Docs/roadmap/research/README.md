# Research behind the 2026-10-07 roadmap

The six research maps (backend, client data, client UI, auth and admin, notifications, tooling) and the live schema notes that the roadmap and the two specs cite are **kept outside the repository** by the owner's decision, because they describe defects that were still open on the live backend when they were written. The specs refer to them as "the backend map", "the notifications map" and so on, with section numbers.

They are dated inventories from 2026-10-06, not a manual: `CLAUDE.md` and `SECURITY.md` remain the authority, and where a map and the code disagree the code wins.

Known errata in the maps, corrected in the specs: the backend map counts 24 client-callable RPCs (a single-line search); the real number is 42. The tooling map quotes 125 string keys as needing positional specifiers; 125 carry at least one, 27 carry two or more.
