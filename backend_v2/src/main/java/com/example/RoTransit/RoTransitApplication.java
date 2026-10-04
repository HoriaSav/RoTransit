package com.example.RoTransit;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.context.annotation.ComponentScan;
import org.springframework.scheduling.annotation.EnableScheduling;

@SpringBootApplication
@EnableScheduling
public class RoTransitApplication {

	public static void main(String[] args) {
		SpringApplication.run(RoTransitApplication.class, args);
	}
}