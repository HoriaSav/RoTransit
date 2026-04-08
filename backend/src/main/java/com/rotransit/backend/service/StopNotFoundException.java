package com.rotransit.backend.service;

public class StopNotFoundException extends RuntimeException {

    public StopNotFoundException(String message) {
        super(message);
    }
}
