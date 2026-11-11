FROM maven:3.9.12-eclipse-temurin-17 AS build
WORKDIR /build

COPY pom.xml .
COPY src ./src

RUN --mount=type=cache,target=/root/.m2 \
    mvn -B -ntp -DskipTests package

FROM gcr.io/distroless/java17-debian13:nonroot
WORKDIR /app

COPY --from=build /build/target/*.jar /app/app.jar

ENV JAVA_TOOL_OPTIONS="-XX:MaxRAMPercentage=75"

EXPOSE 8080 8081
ENTRYPOINT ["java", "-jar", "/app/app.jar"]
