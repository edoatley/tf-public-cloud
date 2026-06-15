package com.example.app;

import org.springframework.boot.actuate.health.Health;
import org.springframework.boot.actuate.health.HealthIndicator;
import org.springframework.stereotype.Component;

import java.util.concurrent.atomic.AtomicBoolean;

@Component
public class ToggleHealthIndicator implements HealthIndicator {

    private final AtomicBoolean healthy = new AtomicBoolean(true);

    @Override
    public Health health() {
        return healthy.get() ? Health.up().build() : Health.down().build();
    }

    public void toggle() {
        healthy.set(!healthy.get());
    }

    void reset() {
        healthy.set(true);
    }

    boolean isHealthy() {
        return healthy.get();
    }
}
