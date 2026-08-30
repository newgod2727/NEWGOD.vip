(function(){
function conv(doc){
  var win = doc.defaultView || window;
  function txt(n){ return (n.innerText || n.textContent || '').replace(/\s+/g,' ').trim(); }
  function cell(c){ return txt(c).replace(/\|/g,'\\|') || ' '; }
  function table(t){
    var rows = [];
    for (var i=0;i<t.rows.length;i++){
      var r = [];
      for (var j=0;j<t.rows[i].cells.length;j++) r.push(cell(t.rows[i].cells[j]));
      if (r.join('').trim()) rows.push(r);
    }
    if (!rows.length) return '';
    var w = 0;
    rows.forEach(function(r){ if (r.length > w) w = r.length; });
    rows.forEach(function(r){ while (r.length < w) r.push(' '); });
    var out = ['| ' + rows[0].join(' | ') + ' |', '|' + new Array(w+1).join('---|')];
    for (var k=1;k<rows.length;k++) out.push('| ' + rows[k].join(' | ') + ' |');
    return out.join('\n');
  }
  function walk(n){
    if (n.nodeType === 3){ var s = n.nodeValue.replace(/\s+/g,' '); return s.trim() ? s : ''; }
    if (n.nodeType !== 1) return '';
    var tag = n.tagName.toLowerCase();
    if (/^(script|style|noscript|svg|head|meta|link|title|iframe|frame)$/.test(tag)) return '';
    try {
      var st = win.getComputedStyle(n);
      if (st && (st.display === 'none' || st.visibility === 'hidden')) return '';
    } catch(e){}
    if (tag === 'table') return '\n\n' + table(n) + '\n\n';
    if (/^h[1-6]$/.test(tag)){ var h = txt(n); return h ? '\n\n## ' + h + '\n\n' : ''; }
    if (tag === 'br') return '\n';
    if (tag === 'hr') return '\n\n---\n\n';
    if (tag === 'img'){ return '![' + (n.getAttribute('alt') || 'image') + '](' + n.src + ')'; }
    if (tag === 'a'){
      var at = txt(n), href = n.getAttribute('href') || '';
      if (!at) return '';
      if (!href || href.charAt(0) === '#' || /^javascript:/i.test(href)) return at;
      return '[' + at + '](' + n.href + ')';
    }
    if (tag === 'option') return '';
    if (tag === 'select'){ var o = n.options[n.selectedIndex]; return o ? txt(o) + ' ' : ''; }
    if (tag === 'textarea') return n.value || '';
    if (tag === 'input'){
      var ty = (n.type || '').toLowerCase();
      if (ty === 'hidden' || ty === 'password') return '';
      if (ty === 'checkbox' || ty === 'radio') return n.checked ? '[x] ' : '[ ] ';
      return n.value ? n.value + ' ' : '';
    }
    var inner = '';
    for (var i=0;i<n.childNodes.length;i++) inner += walk(n.childNodes[i]);
    if (tag === 'li') return '\n- ' + inner.replace(/\s+/g,' ').trim();
    if (/^(p|div|section|article|tr|ul|ol|form|header|footer|main|nav|blockquote|dl|dt|dd|fieldset|td|th|span)$/.test(tag)){
      return /^(td|th|span)$/.test(tag) ? inner : '\n\n' + inner + '\n\n';
    }
    return inner;
  }
  return walk(doc.body || doc.documentElement);
}
function grab(win, label, depth, acc){
  if (depth > 4) return;
  var d;
  try { d = win.document; } catch(e){ return; }
  if (!d) return;
  var body = conv(d);
  if (body.replace(/\s/g,'').length > 2) acc.push((label ? '\n\n## ' + label + '\n\n' : '') + body);
  for (var i=0;i<win.frames.length;i++){
    try {
      var f = win.frames[i], el = f.frameElement;
      grab(f, (el && (el.name || el.id)) || ('frame ' + i), depth + 1, acc);
    } catch(e){}
  }
}
var acc = [];
grab(window, '', 0, acc);
var body = acc.join('\n\n').replace(/[ \t]+\n/g,'\n').replace(/\n{3,}/g,'\n\n').trim();
var head = '## ' + (document.title || 'page') + '\n\n## ' + location.href + '\n\n## ' + new Date().toString() + '\n\n---\n';
var text = head + '\n' + body + '\n';
var name = (document.title || 'page').replace(/[\\\/:*?"<>|]+/g,'-').replace(/\s+/g,' ').trim().slice(0,60) + '.md';
try {
  var b = new Blob([text], {type:'text/markdown;charset=utf-8'});
  var a = document.createElement('a');
  a.href = URL.createObjectURL(b);
  a.download = name;
  document.body.appendChild(a);
  a.click();
  setTimeout(function(){ URL.revokeObjectURL(a.href); a.remove(); }, 3000);
  console.log('saved: ' + name + '  (' + text.length + ' chars, ' + acc.length + ' frames)');
} catch(e){
  console.log('download blocked, copy from here:');
  console.log(text);
}
return text.length;
})();
