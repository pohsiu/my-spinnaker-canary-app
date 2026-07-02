# my-spinnaker-canary-app

Demo project showing a web service deployed via Helm and progressively rolled out
with a Spinnaker + Kayenta canary pipeline.

```
.images/       # app source + Dockerfile (Prometheus-instrumented Node service)
helm/          # Helm chart (production/baseline/canary via .Values.track)
spinnaker/     # Dinghyfile pipeline-as-code + Kayenta canary metric config
```

## Local run

```
cd .images
npm install
npm start
```

Serves on `:3000`, with app traffic at `/` and Prometheus metrics at `/metrics`.
