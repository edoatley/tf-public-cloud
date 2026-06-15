package com.example.app;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.test.web.servlet.MockMvc;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

@WebMvcTest(ItemController.class)
class ItemControllerTest {

    @Autowired
    MockMvc mvc;

    @Test
    void list_returns_all_three_items() throws Exception {
        mvc.perform(get("/api/items"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.length()").value(3))
                .andExpect(jsonPath("$[0].id").value(1))
                .andExpect(jsonPath("$[0].name").value("Widget"))
                .andExpect(jsonPath("$[1].name").value("Gadget"))
                .andExpect(jsonPath("$[2].name").value("Doohickey"));
    }

    @Test
    void get_returns_item_by_id() throws Exception {
        mvc.perform(get("/api/items/2"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.id").value(2))
                .andExpect(jsonPath("$.name").value("Gadget"))
                .andExpect(jsonPath("$.description").value("A handy electronic device"));
    }

    @Test
    void get_returns_404_for_unknown_id() throws Exception {
        mvc.perform(get("/api/items/99"))
                .andExpect(status().isNotFound());
    }
}
