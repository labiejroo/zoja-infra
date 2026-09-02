function handler(event) {
    var request = event.request;
    var uri = request.uri;

    if (uri === '/') {
        request.uri = '/index.html';
        return request;
    }

    // Później /api będzie obsługiwane przez API Gateway,
    // więc nie chcemy go przepisywać na .html.
    if (uri === '/api' || uri.indexOf('/api/') === 0) {
        return request;
    }

    // Jeśli URL nie wskazuje już na konkretny plik
    if (uri.indexOf('.') === -1) {
        if (uri.slice(-1) === '/') {
            uri = uri.slice(0, -1);
        }

        request.uri = uri + '.html';
    }

    return request;
}