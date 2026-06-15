package com.example.app;

import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.Map;

@RestController
@RequestMapping("/health")
public class HealthController {

    private final ToggleHealthIndicator indicator;

    public HealthController(ToggleHealthIndicator indicator) {
        this.indicator = indicator;
    }

    @PostMapping("/toggle")
    public ResponseEntity<Map<String, String>> toggle() {
        indicator.toggle();
        String status = indicator.isHealthy() ? "UP" : "DOWN";
        return ResponseEntity.ok(Map.of("status", status));
    }
}
