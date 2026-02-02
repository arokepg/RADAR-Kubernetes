# Zip the contents into a JAR
# zip -r restructure-scope.jar restructure-mapper/restructure-scope.js META-INF/keycloak-scripts.json
# Next, create docker image like so:
# docker build -t pvannierop/keycloak-scope-mapper:0.7.0 .
cp ../../../keycloak-custom-scopes-extension/build/libs/keycloak-custom-scopes-extension-*.jar .
docker build -t pvannierop/keycloak-scope-mapper:$1 .
docker push pvannierop/keycloak-scope-mapper:$1
