#!/usr/bin/env python3
"""Generate a professional Dice Protocol whitepaper PDF."""

import re
from pathlib import Path

def md_to_pdf():
    with open('/root/dice-protocol/docs/whitepaper.md') as f:
        md = f.read()

    lines = md.split('\n')
    body_html = []
    in_code_block = False
    in_table = False
    table_rows = []
    code_lines = []

    i = 0
    while i < len(lines):
        line = lines[i]

        if line.strip().startswith('```'):
            if in_code_block:
                code_text = '\n'.join(code_lines)
                escaped = code_text.replace('&', '&amp;').replace('<', '&lt;').replace('>', '&gt;')
                body_html.append(f'<div class="code-block"><pre><code>{escaped}</code></pre></div>')
                code_lines = []
                in_code_block = False
            else:
                in_code_block = True
            i += 1
            continue

        if in_code_block:
            code_lines.append(line)
            i += 1
            continue

        if line.strip().startswith('|') and line.strip().endswith('|'):
            if not in_table:
                in_table = True
                table_rows = []
            if re.match(r'^\|[\s\-:|]+\|$', line.strip()):
                i += 1
                continue
            cells = [c.strip() for c in line.strip().strip('|').split('|')]
            table_rows.append(cells)
            i += 1
            continue
        elif in_table:
            if table_rows:
                thead = '<tr>' + ''.join(f'<th>{c}</th>' for c in table_rows[0]) + '</tr>'
                tbody = ''
                for row in table_rows[1:]:
                    cells_html = ''
                    for c in row:
                        c = re.sub(r'`([^`]+)`', r'<code class="inline">\1</code>', c)
                        c = re.sub(r'\*\*([^*]+)\*\*', r'<strong>\1</strong>', c)
                        cells_html += f'<td>{c}</td>'
                    tbody += f'<tr>{cells_html}</tr>'
                body_html.append(f'<table><thead>{thead}</thead><tbody>{tbody}</tbody></table>')
            in_table = False
            table_rows = []

        if line.startswith('# ') and not line.startswith('## '):
            text = line[2:].strip()
            body_html.append(f'<h1>{text}</h1>')
        elif line.startswith('### '):
            text = line[4:].strip()
            text = re.sub(r'`([^`]+)`', r'<code class="inline">\1</code>', text)
            body_html.append(f'<h3>{text}</h3>')
        elif line.startswith('## '):
            text = line[3:].strip()
            text = re.sub(r'`([^`]+)`', r'<code class="inline">\1</code>', text)
            body_html.append(f'<h2>{text}</h2>')
        elif line.strip() == '---':
            body_html.append('<hr>')
        elif re.match(r'^[\-\d]+\.\s', line.strip()) or line.strip().startswith('- '):
            text = line.strip()
            text = re.sub(r'^[-\d.]+\s*', '', text)
            text = re.sub(r'\*\*([^*]+)\*\*', r'<strong>\1</strong>', text)
            text = re.sub(r'`([^`]+)`', r'<code class="inline">\1</code>', text)
            body_html.append(f'<div class="list-item">{text}</div>')
        elif line.strip() == '':
            pass  # Skip empty lines - CSS handles spacing
        else:
            text = line.strip()
            text = re.sub(r'\*\*([^*]+)\*\*', r'<strong>\1</strong>', text)
            text = re.sub(r'`([^`]+)`', r'<code class="inline">\1</code>', text)
            text = re.sub(r'\*([^*]+)\*', r'<em>\1</em>', text)
            body_html.append(f'<p>{text}</p>')

        i += 1

    if in_table and table_rows:
        thead = '<tr>' + ''.join(f'<th>{c}</th>' for c in table_rows[0]) + '</tr>'
        tbody = ''
        for row in table_rows[1:]:
            cells_html = ''
            for c in row:
                c = re.sub(r'`([^`]+)`', r'<code class="inline">\1</code>', c)
                c = re.sub(r'\*\*([^*]+)\*\*', r'<strong>\1</strong>', c)
                cells_html += f'<td>{c}</td>'
            tbody += f'<tr>{cells_html}</tr>'
        body_html.append(f'<table><thead>{thead}</thead><tbody>{tbody}</tbody></table>')

    body_content = '\n'.join(body_html)

    html = f"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<style>
@page {{
    size: A4;
    margin: 22mm 18mm 25mm 18mm;
    @bottom-center {{
        content: counter(page);
        font-family: 'Helvetica Neue', sans-serif;
        font-size: 9px;
        color: #888;
    }}
    @bottom-left {{
        content: "Dice Protocol Whitepaper v1.0";
        font-family: 'Helvetica Neue', sans-serif;
        font-size: 8px;
        color: #aaa;
    }}
    @bottom-right {{
        content: "diceprotocol.world";
        font-family: 'Helvetica Neue', sans-serif;
        font-size: 8px;
        color: #aaa;
    }}
}}

@page :first {{
    margin: 0;
    @bottom-center {{ content: none; }}
    @bottom-left {{ content: none; }}
    @bottom-right {{ content: none; }}
}}

* {{ box-sizing: border-box; margin: 0; padding: 0; }}

body {{
    font-family: 'Helvetica Neue', 'Arial', sans-serif;
    font-size: 11px;
    line-height: 1.6;
    color: #1a1a2e;
    -webkit-font-smoothing: antialiased;
}}

/* ===== COVER PAGE ===== */
.cover {{
    page-break-after: always;
    height: 297mm;
    background: #0a0a0f;
    color: #fff;
    position: relative;
    display: flex;
    flex-direction: column;
    overflow: hidden;
}}

.cover-bg {{
    position: absolute;
    top: 0; left: 0; right: 0; bottom: 0;
    background:
        radial-gradient(ellipse 600px 400px at 15% 10%, rgba(99, 102, 241, 0.12) 0%, transparent 60%),
        radial-gradient(ellipse 500px 500px at 85% 90%, rgba(139, 92, 246, 0.08) 0%, transparent 60%),
        radial-gradient(ellipse 400px 300px at 50% 50%, rgba(67, 56, 202, 0.05) 0%, transparent 70%);
    pointer-events: none;
}}

/* Faint grid pattern */
.cover-grid {{
    position: absolute;
    top: 0; left: 0; right: 0; bottom: 0;
    background-image:
        linear-gradient(rgba(255,255,255,0.015) 1px, transparent 1px),
        linear-gradient(90deg, rgba(255,255,255,0.015) 1px, transparent 1px);
    background-size: 40px 40px;
    pointer-events: none;
}}

.cover-top {{
    padding: 35mm 25mm 0 25mm;
    position: relative;
    z-index: 2;
}}

.cover-eye {{
    width: 56px;
    height: 56px;
    margin-bottom: 10mm;
    position: relative;
}}

.cover-eye svg {{
    width: 100%;
    height: 100%;
}}

.cover-label {{
    font-size: 10px;
    text-transform: uppercase;
    letter-spacing: 4px;
    color: #666;
    font-weight: 600;
}}

.cover-center {{
    padding: 0 25mm;
    position: relative;
    z-index: 2;
    flex-grow: 1;
    display: flex;
    flex-direction: column;
    justify-content: center;
}}

.cover-title {{
    font-size: 52px;
    font-weight: 800;
    letter-spacing: -1.5px;
    line-height: 1.0;
    margin-bottom: 8mm;
}}

.cover-subtitle {{
    font-size: 15px;
    font-weight: 300;
    color: #9090a8;
    line-height: 1.55;
    max-width: 130mm;
}}

.cover-divider {{
    width: 60px;
    height: 3px;
    background: #4338ca;
    margin: 12mm 0;
    border-radius: 2px;
}}

.cover-meta {{
    display: flex;
    gap: 12mm;
}}

.cover-meta-item {{
    display: flex;
    flex-direction: column;
}}

.cover-meta-label {{
    font-size: 8px;
    text-transform: uppercase;
    letter-spacing: 1.5px;
    color: #444;
    margin-bottom: 3mm;
}}

.cover-meta-value {{
    font-size: 13px;
    font-weight: 600;
    color: #b0b0c8;
    font-family: 'Courier New', monospace;
}}

.cover-bottom {{
    padding: 0 25mm 25mm 25mm;
    position: relative;
    z-index: 2;
    display: flex;
    justify-content: space-between;
    align-items: flex-end;
}}

.cover-url {{
    font-size: 12px;
    color: #707090;
    font-family: 'Courier New', monospace;
    letter-spacing: 0.5px;
}}

.cover-version {{
    font-size: 10px;
    color: #505060;
    text-align: right;
}}

/* ===== CONTENT PAGES ===== */
h1 {{
    font-size: 20px;
    font-weight: 700;
    color: #0a0a0f;
    margin-top: 8px;
    margin-bottom: 10px;
    padding-bottom: 5px;
    border-bottom: 2px solid #0a0a0f;
    page-break-before: always;
    page-break-after: avoid;
}}

h1:first-of-type {{
    page-break-before: avoid;
}}

h2 {{
    font-size: 14px;
    font-weight: 700;
    color: #0a0a0f;
    margin-top: 16px;
    margin-bottom: 6px;
    page-break-after: avoid;
}}

h3 {{
    font-size: 12px;
    font-weight: 600;
    color: #2a2a3e;
    margin-top: 12px;
    margin-bottom: 4px;
    page-break-after: avoid;
}}

p {{
    margin-bottom: 5px;
    text-align: justify;
}}

strong {{
    font-weight: 700;
    color: #0a0a0f;
}}

hr {{
    border: none;
    border-top: 1px solid #e0e0e0;
    margin: 12px 0;
}}

/* ===== TABLES ===== */
table {{
    width: 100%;
    border-collapse: collapse;
    margin: 8px 0 10px 0;
    font-size: 9.5px;
    page-break-inside: avoid;
}}

th {{
    background: #0a0a0f;
    color: #fff;
    padding: 7px 10px;
    text-align: left;
    font-weight: 600;
    font-size: 9px;
    text-transform: uppercase;
    letter-spacing: 0.3px;
}}

td {{
    padding: 6px 10px;
    border-bottom: 1px solid #e8e8e8;
    vertical-align: top;
}}

tr:nth-child(even) td {{
    background: #f7f7fc;
}}

/* ===== CODE ===== */
code.inline {{
    font-family: 'Courier New', monospace;
    font-size: 9.5px;
    background: #eef0f8;
    padding: 1px 5px;
    border-radius: 3px;
    color: #4338ca;
}}

.code-block {{
    background: #0a0a0f;
    border-radius: 6px;
    padding: 12px 14px;
    margin: 8px 0 10px 0;
    overflow-x: auto;
    page-break-inside: avoid;
}}

.code-block pre {{ margin: 0; }}

.code-block code {{
    font-family: 'Courier New', monospace;
    font-size: 8.5px;
    line-height: 1.55;
    color: #c0c0d8;
    white-space: pre;
}}

/* ===== LISTS ===== */
.list-item {{
    padding-left: 14px;
    position: relative;
    margin-bottom: 3px;
    text-align: justify;
}}

.list-item::before {{
    content: '';
    position: absolute;
    left: 0;
    top: 7px;
    width: 4px;
    height: 4px;
    border-radius: 50%;
    background: #4338ca;
}}
</style>
</head>
<body>

<!-- COVER PAGE -->
<div class="cover">
    <div class="cover-bg"></div>
    <div class="cover-grid"></div>
    <div class="cover-top">
        <div class="cover-eye">
            <svg viewBox="0 0 100 100" fill="none" xmlns="http://www.w3.org/2000/svg">
                <path d="M50 15 C20 15 5 50 5 50 C5 50 20 85 50 85 C80 85 95 50 95 50 C95 50 80 15 50 15Z" stroke="white" stroke-width="2" fill="none"/>
                <circle cx="50" cy="50" r="18" fill="white"/>
                <circle cx="50" cy="50" r="8" fill="#0a0a0f"/>
                <circle cx="53" cy="47" r="3" fill="white"/>
            </svg>
        </div>
        <div class="cover-label">Technical Whitepaper</div>
    </div>
    <div class="cover-center">
        <div class="cover-title">Dice Protocol</div>
        <div class="cover-subtitle">A commit-reveal randomness oracle for Robinhood Chain, delivering unbiased, verifiable onchain randomness through hash-chain commitments.</div>
        <div class="cover-divider"></div>
        <div class="cover-meta">
            <div class="cover-meta-item">
                <div class="cover-meta-label">Version</div>
                <div class="cover-meta-value">1.0</div>
            </div>
            <div class="cover-meta-item">
                <div class="cover-meta-label">Chain</div>
                <div class="cover-meta-value">4663</div>
            </div>
            <div class="cover-meta-item">
                <div class="cover-meta-label">Fee</div>
                <div class="cover-meta-value">0.000025 ETH</div>
            </div>
            <div class="cover-meta-item">
                <div class="cover-meta-label">Latency</div>
                <div class="cover-meta-value">~3.5s</div>
            </div>
        </div>
    </div>
    <div class="cover-bottom">
        <div class="cover-url">diceprotocol.world</div>
        <div class="cover-version">July 2026</div>
    </div>
</div>

<!-- BODY -->
{body_content}

</body>
</html>"""

    html_path = '/tmp/whitepaper_pro.html'
    with open(html_path, 'w') as f:
        f.write(html)

    from playwright.sync_api import sync_playwright

    with sync_playwright() as p:
        browser = p.chromium.launch(headless=True)
        page = browser.new_page()
        page.goto(f'file://{html_path}')
        page.pdf(
            path='/tmp/dice-protocol-whitepaper.pdf',
            format='A4',
            print_background=True,
            prefer_css_page_size=True,
        )
        browser.close()

    size = Path('/tmp/dice-protocol-whitepaper.pdf').stat().st_size
    print(f"PDF generated: {size:,} bytes")

if __name__ == '__main__':
    md_to_pdf()
