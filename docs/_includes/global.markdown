<!-- TODO: Change this to latest release -->
{% assign release = site.github.releases[0] %}

{% assign windowsDownload = false %}
{% assign linuxDownload = false %}
{% assign macDownload = false %}
{% assign androidDownload = false %}

{% for a in release.assets %}
{% if a.name contains "_linux64.zip" %}
{% assign linuxDownload = a.browser_download_url %}
{% endif %}
{% if a.name contains "_windows64.zip" %}
{% assign windowsDownload = a.browser_download_url %}
{% endif %}
{% if a.name contains "_android.apk" %}
{% assign androidDownload = a.browser_download_url %}
{% endif %}
{% endfor %}

{% assign isHome = false %}
{% if page.url == "/index.html" or page.url == "/" %}
   {% assign isHome = true %}
{% endif %}

{% assign isDocumentation = false %}
{% if page.url contains "/docs/" %}
   {% assign isDocumentation = true %}
{% endif %}
