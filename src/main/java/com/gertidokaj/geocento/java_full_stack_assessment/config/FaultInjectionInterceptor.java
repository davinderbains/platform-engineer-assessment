package com.gertidokaj.geocento.java_full_stack_assessment.config;

import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.MediaType;
import org.springframework.web.servlet.HandlerInterceptor;

import java.util.concurrent.ThreadLocalRandom;

public class FaultInjectionInterceptor implements HandlerInterceptor {

    private static final Logger log = LoggerFactory.getLogger(FaultInjectionInterceptor.class);

    private final double rate;

    public FaultInjectionInterceptor(double rate) {
        this.rate = rate;
    }

    @Override
    public boolean preHandle(HttpServletRequest request, HttpServletResponse response, Object handler)
            throws Exception {

        if (ThreadLocalRandom.current().nextDouble() >= rate) {
            return true;
        }

        log.warn("Injected failure on {} (FAULT_ERROR_RATE={})", request.getRequestURI(), rate);

        response.setStatus(HttpServletResponse.SC_INTERNAL_SERVER_ERROR);
        response.setContentType(MediaType.APPLICATION_JSON_VALUE);
        response.getWriter().write("""
                {"error":"Injected failure (FAULT_ERROR_RATE)"}
                """);

        return false;
    }
}
