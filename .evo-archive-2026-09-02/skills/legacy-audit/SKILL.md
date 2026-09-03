# Legacy Audit Skill

For each inherited subsystem, answer:
- What calls it?
- What files/config does it read/write?
- What database tables does it touch?
- What shell commands does it execute?
- What Asterisk interfaces does it assume?
- What filesystem ownership/permissions does it require?
- Is the behavior application logic or installation-environment logic?

Prefer repository evidence over assumptions.
Produce concise findings with file paths and migration implications.
