// HarbourBuilder Documentation - JavaScript
// Theme toggle, search, copy code, navigation

// Theme toggle
function toggleTheme() {
  const html = document.documentElement;
  const current = html.getAttribute('data-theme');
  const next = current === 'light' ? 'dark' : 'light';
  html.setAttribute('data-theme', next);
  localStorage.setItem('hb-theme', next);
  document.querySelector('.theme-toggle').textContent = next === 'light' ? '\u263E' : '\u2600';
}

// Init theme
(function() {
  const saved = localStorage.getItem('hb-theme') || 'dark';
  document.documentElement.setAttribute('data-theme', saved);
})();

// Copy code button
document.addEventListener('DOMContentLoaded', function() {
  document.querySelectorAll('pre').forEach(function(block) {
    var btn = document.createElement('button');
    btn.className = 'copy-btn';
    btn.textContent = 'Copy';
    btn.onclick = function() {
      navigator.clipboard.writeText(block.textContent.replace('Copy', '').trim());
      btn.textContent = 'Copied!';
      setTimeout(function() { btn.textContent = 'Copy'; }, 2000);
    };
    block.style.position = 'relative';
    block.appendChild(btn);
  });

  // Active sidebar link
  var path = window.location.pathname;
  document.querySelectorAll('.sidebar a').forEach(function(a) {
    if (a.getAttribute('href') && path.indexOf(a.getAttribute('href')) >= 0)
      a.classList.add('active');
  });
});

// Simple search filter
function doSearch(query) {
  query = query.toLowerCase();
  document.querySelectorAll('.sidebar a').forEach(function(a) {
    var text = a.textContent.toLowerCase();
    a.style.display = text.indexOf(query) >= 0 || query === '' ? '' : 'none';
  });
}
