package com.rotransit.backend.controller;

import com.rotransit.backend.otp.OtpException;
import com.rotransit.backend.config.RequestCorrelationFilter;
import com.rotransit.backend.service.CityNotFoundException;
import com.rotransit.backend.service.SavedRouteNotFoundException;
import com.rotransit.backend.service.StopNotFoundException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.validation.ConstraintViolationException;
import java.time.Instant;
import java.util.Map;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.MethodArgumentNotValidException;
import org.springframework.web.bind.MissingServletRequestParameterException;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestControllerAdvice;
import org.springframework.web.servlet.resource.NoResourceFoundException;

@RestControllerAdvice
public class ApiExceptionHandler {
    private static final Logger log = LoggerFactory.getLogger(ApiExceptionHandler.class);

    @ExceptionHandler(CityNotFoundException.class)
    @ResponseStatus(HttpStatus.NOT_FOUND)
    public ApiErrorResponse handleCityNotFound(CityNotFoundException ex, HttpServletRequest request) {
        return error(
                "CITY_NOT_FOUND",
                ex.getMessage(),
                request,
                Map.of()
        );
    }

    @ExceptionHandler(SavedRouteNotFoundException.class)
    @ResponseStatus(HttpStatus.NOT_FOUND)
    public ApiErrorResponse handleSavedRouteNotFound(SavedRouteNotFoundException ex, HttpServletRequest request) {
        return error(
                "SAVED_ROUTE_NOT_FOUND",
                ex.getMessage(),
                request,
                Map.of()
        );
    }

    @ExceptionHandler(StopNotFoundException.class)
    @ResponseStatus(HttpStatus.NOT_FOUND)
    public ApiErrorResponse handleStopNotFound(StopNotFoundException ex, HttpServletRequest request) {
        return error(
                "STOP_NOT_FOUND",
                ex.getMessage(),
                request,
                Map.of()
        );
    }

    @ExceptionHandler({
            ConstraintViolationException.class,
            MethodArgumentNotValidException.class,
            MissingServletRequestParameterException.class
    })
    @ResponseStatus(HttpStatus.BAD_REQUEST)
    public ApiErrorResponse handleValidation(Exception ex, HttpServletRequest request) {
        return error(
                "VALIDATION_ERROR",
                ex.getMessage(),
                request,
                Map.of("exceptionType", ex.getClass().getSimpleName())
        );
    }

    @ExceptionHandler(OtpException.class)
    @ResponseStatus(HttpStatus.BAD_GATEWAY)
    public ApiErrorResponse handleOtpError(OtpException ex, HttpServletRequest request) {
        log.warn("Upstream OTP error: {}", ex.getMessage());
        return error(
                "OTP_UPSTREAM_ERROR",
                ex.getMessage(),
                request,
                Map.of("upstream", "otp")
        );
    }

    @ExceptionHandler(NoResourceFoundException.class)
    @ResponseStatus(HttpStatus.NOT_FOUND)
    public ApiErrorResponse handleNoResourceFound(NoResourceFoundException ex, HttpServletRequest request) {
        log.warn("No resource: {}", ex.getResourcePath());
        return error(
                "NOT_FOUND",
                "No handler for this path (deploy a backend build that includes the route, or check the URL).",
                request,
                Map.of(
                        "exceptionType", ex.getClass().getSimpleName(),
                        "resourcePath", ex.getResourcePath()
                )
        );
    }

    @ExceptionHandler(Exception.class)
    @ResponseStatus(HttpStatus.INTERNAL_SERVER_ERROR)
    public ApiErrorResponse handleUnexpected(Exception ex, HttpServletRequest request) {
        log.error("Unhandled API exception", ex);
        return error(
                "INTERNAL_ERROR",
                "Unexpected error",
                request,
                Map.of("exceptionType", ex.getClass().getSimpleName())
        );
    }

    private ApiErrorResponse error(
            String code,
            String message,
            HttpServletRequest request,
            Map<String, Object> details
    ) {
        String requestId = String.valueOf(request.getAttribute(RequestCorrelationFilter.REQUEST_ID_ATTR));
        return new ApiErrorResponse(
                Instant.now(),
                code,
                code,
                message,
                requestId,
                details
        );
    }
}
