"""Run existing acceptance fixtures through the production area interface.

This migration is restricted to known synthetic fixture methods, not host
application source. It lifts their configuration into AXB_Configure and removes
their one-shot lifecycle calls, leaving business initialization and timers.
"""
import json
import re
from install_host_methods import area_form


def integrate(sources, method_forms):
    methods = sources / "Methods"
    cases = []
    for method, form_name in method_forms.items():
        path = methods / (method + ".4dm")
        lines = path.read_text().splitlines()
        starts = [i for i, line in enumerate(lines) if ':=AXB_Form("start";' in line]
        if len(starts) != 1:
            raise ValueError("Area fixture migration requires one startup in " + method)
        start = starts[0]
        match = re.fullmatch(r'\s*[^:]+:=AXB_Form\("start"; (.*)\)', lines[start])
        if not match:
            raise ValueError("Unknown fixture startup: " + lines[start])
        expression = match[1]
        # These fixtures use straight-line option construction. Configuration
        # callbacks remain host formulas and keep the exact existing bindings.
        config = []
        kept = []
        for i, line in enumerate(lines):
            stripped = line.strip()
            if i < start and (stripped.startswith(("$options:=", "$options.", "$child:=", "$child.", "Form.providerOptions:=$options"))):
                config.append(stripped)
            elif i == start or (i == start + 1 and re.fullmatch(r'Form\.(start|startResult):=\$\w+', stripped)):
                continue
            elif ':=AXB_Form("stop";' in line:
                continue
            else:
                kept.append(line)
        # Remove a now-empty On Unload branch rather than leaving dead scaffolding.
        content = "\n".join(kept) + "\n"
        content = re.sub(r'\n\s*: \(Form event code=On Unload\)\n(?=End case)', '\n', content)
        content = re.sub(r'^\s*If \([^\n]*\)\n\s*End if\n', '', content, flags=re.MULTILINE)
        # Drop locals used only by the removed lifecycle/configuration code.
        # This applies to our known synthetic methods, never application code.
        body = re.sub(r'^\s*var .*$', '', content, flags=re.MULTILINE)
        def declarations(match):
            names = [name.strip() for name in match[2].split(';')]
            kept_names = [name for name in names if re.search(re.escape(name) + r'\b', body)]
            return match[1] + 'var ' + '; '.join(kept_names) + ' : Object' if kept_names else ''
        content = re.sub(r'^(\s*)var ((?:\$\w+\s*;\s*)*\$\w+)\s*:\s*Object$', declarations, content, flags=re.MULTILINE)
        path.write_text(content)
        cases.append(' : ($formName=' + json.dumps(form_name) + ')\n  ' + '\n  '.join(config + ['$options:=' + expression]))
    child_declaration = 'var $child : Object\n' if any('$child' in case for case in cases) else ''
    (methods / "AXB_Configure.4dm").write_text('#DECLARE($formName : Text) -> $options : Object\n' + child_declaration + 'Case of\n' + '\n'.join(cases) + '\nEnd case\n')
    # Readiness reports read the actual registered lifetime. No startup result
    # is fabricated and the AX tests still await the published native provider.
    for path in methods.glob("*.4dm"):
        if path.stem.startswith(("AXB_", "Compiler_")):
            continue
        content = path.read_text()
        for old in ("Form.startResult", "Form.start", "AXBC_RootStart"):
            content = re.sub(r'\b' + re.escape(old) + r'\b(?!\s*:=)', 'AreaTestStart', content)
        path.write_text(content)
    (methods / "AreaTestStart.4dm").write_text('#DECLARE() -> $result : Object\nvar $context : Object\n$context:=AXB_FormContext\n$result:=New object("ok"; (($context#Null) && ($context.active=True)); "session"; $context.session)\n')
    compiler = methods / "Compiler_AreaTest.4dm"
    compiler.write_text('C_TEXT(AXB_Configure; $1)\nC_OBJECT(AXB_Configure; $0)\nC_OBJECT(AreaTestStart; $0)\n')
    for path in sources.rglob("form.4DForm"):
        path.write_text(json.dumps(area_form(json.loads(path.read_text())), indent=2) + "\n")
