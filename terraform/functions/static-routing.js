// CloudFront Function (viewer request) — routing tras statycznych.
//
// UWAGA: to jest ODWZOROWANIE funkcji, która już działa w AWS. Przy imporcie
// CloudFront zwróci swój faktyczny kod i Terraform porówna go co do bajta.
// Jeśli plan pokaże różnicę, NIE zmieniaj funkcji w AWS — podmień ten plik na
// dokładną treść z konsoli albo z `terraform show`.
//
// Zadanie: Next.js z output "export" generuje płaskie pliki (admin.html,
// decision.html, cancel.html), a CloudFront z originem S3 nie rozwiązuje
// adresów bez rozszerzenia. Bez tego mapowania /admin zwraca 404.
//
// Czego ta funkcja NIE robi: nie dotyka tokenów. Linki mają postać
// /decision?t=<token>, więc token jedzie w query stringu i przechodzi nietknięty.

function handler(event) {
  var request = event.request;
  var uri = request.uri;

  // Katalog główny -> dokument startowy.
  if (uri === "/" || uri === "") {
    request.uri = "/index.html";
    return request;
  }

  // Zasoby z rozszerzeniem (JS, CSS, obrazy, /_next/*) zostawiamy w spokoju.
  var lastSegment = uri.substring(uri.lastIndexOf("/") + 1);
  if (lastSegment.indexOf(".") !== -1) {
    return request;
  }

  // Adres kończący się ukośnikiem: /admin/ -> /admin.html
  if (uri.charAt(uri.length - 1) === "/") {
    request.uri = uri.slice(0, -1) + ".html";
    return request;
  }

  // Adres bez rozszerzenia: /admin -> /admin.html
  request.uri = uri + ".html";
  return request;
}
