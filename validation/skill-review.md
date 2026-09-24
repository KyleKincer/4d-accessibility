# Integration skill review

On September 24, 2026, Claude Opus 5.5 reviewed the installed skill folder and checked API claims against the canonical source. The final correction review rated it **8.5/10**. Earlier passes identified unclear acquisition and ownership rules, unsafe generated-root restart advice, stale AreaList key requirements and missing external action instructions. Those findings were corrected and the reviewer verified the changes.

The final pass found four smaller issues: missing native-array key/selection constraints, a missing output-directory step, stale legacy-example instructions and inconsistent optional-package checks. The documentation now states the native adapter's Text-key limitation and directs numeric bindings to bridge work; creates the inspector output directory; corrects the examples; and makes optional-package checks conditional on the host's policy. These final edits have local link/skill validation and source checks, but no additional numerical rating.

The review rated the integration instructions, not implementation completeness. Unsupported control families and pending application/assistive-technology tests remain in the status document. The external inspector and action recipe were also exercised against an isolated live 4D form; see `external-ax-tools.json`.
