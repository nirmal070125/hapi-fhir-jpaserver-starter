FROM maven:3.8.5-eclipse-temurin-18-alpine as build-hapi 
WORKDIR /tmp/hapi-fhir-jpaserver-starter

ARG OPENTELEMETRY_JAVA_AGENT_VERSION=1.17.0
RUN curl -LSsO https://github.com/open-telemetry/opentelemetry-java-instrumentation/releases/download/v${OPENTELEMETRY_JAVA_AGENT_VERSION}/opentelemetry-javaagent.jar

COPY pom.xml .
COPY server.xml .
RUN mvn -ntp dependency:go-offline

COPY src/ /tmp/hapi-fhir-jpaserver-starter/src/
RUN mvn clean install -DskipTests -Djdk.lang.Process.launchMechanism=vfork

FROM build-hapi AS build-distroless
RUN mvn package spring-boot:repackage -Pboot
RUN mkdir /app && cp /tmp/hapi-fhir-jpaserver-starter/target/ROOT.war /app/main.war


########### bitnami tomcat version is suitable for debugging and comes with a shell
########### it can be built using eg. `docker build --target tomcat .`
FROM bitnami/tomcat:9.0 as tomcat

RUN rm -rf /opt/bitnami/tomcat/webapps/ROOT && \
    mkdir -p /opt/bitnami/hapi/data/hapi/lucenefiles && \
    chmod 775 /opt/bitnami/hapi/data/hapi/lucenefiles

RUN useradd -r -u 10001 -g appuser appuser
USER 10001

RUN mkdir -p /target && chown -R 10001:10001 target

COPY --chown=10001:10001 catalina.properties /opt/bitnami/tomcat/conf/catalina.properties
COPY --chown=10001:10001 server.xml /opt/bitnami/tomcat/conf/server.xml
COPY --from=build-hapi --chown=10001:10001 /tmp/hapi-fhir-jpaserver-starter/target/ROOT.war /opt/bitnami/tomcat/webapps/ROOT.war
COPY --from=build-hapi --chown=10001:10001 /tmp/hapi-fhir-jpaserver-starter/opentelemetry-javaagent.jar /app

ENV ALLOW_EMPTY_PASSWORD=yes

########### distroless brings focus on security and runs on plain spring boot - this is the default image
FROM openjdk:18-alpine

# https://security.alpinelinux.org/vuln/CVE-2022-37434
RUN apk update && apk upgrade zlib
RUN apk add libtasn1=4.18.0-r1

USER 10014
WORKDIR /app

COPY --chown=10014:10014 --from=build-distroless /app /app
COPY --chown=10014:10014 --from=build-hapi /tmp/hapi-fhir-jpaserver-starter/opentelemetry-javaagent.jar /app

CMD ["/app/main.war"]
