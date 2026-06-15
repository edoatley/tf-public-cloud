package com.example.app;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.context.annotation.Import;
import org.springframework.test.web.servlet.MockMvc;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

@WebMvcTest(HealthController.class)
@Import(ToggleHealthIndicator.class)
class HealthControllerTest {

    @Autowired
    MockMvc mvc;

    @Autowired
    ToggleHealthIndicator indicator;

    @BeforeEach
    void resetHealth() {
        indicator.reset();
    }

    @Test
    void toggle_returns_down_on_first_call() throws Exception {
        mvc.perform(post("/health/toggle"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.status").value("DOWN"));
    }

    @Test
    void toggle_returns_up_on_second_call() throws Exception {
        mvc.perform(post("/health/toggle"));

        mvc.perform(post("/health/toggle"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.status").value("UP"));
    }
}
