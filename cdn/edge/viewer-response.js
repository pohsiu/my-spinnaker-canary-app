// CloudFront Function — viewer-response
//
// Pins the bucket decision made in viewer-request.js to a cookie so repeat
// visits (and every asset request on the page) stay on the same version —
// without this, a visitor could get index.html from canary and hashed JS
// chunks from stable, which is a broken page.

function handler(event) {
  const request = event.request;
  const response = event.response;
  const decision = request.headers['x-app-bucket-decision'];

  if (decision) {
    response.cookies['app-bucket'] = {
      value: decision.value,
      attributes: 'Path=/; Max-Age=3600; SameSite=Lax',
    };
  }

  return response;
}
