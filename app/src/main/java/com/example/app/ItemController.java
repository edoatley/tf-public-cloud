package com.example.app;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;

@RestController
@RequestMapping("/api/items")
public class ItemController {

    private static final List<Item> ITEMS = List.of(
        new Item(1, "Widget", "A small reusable component"),
        new Item(2, "Gadget", "A handy electronic device"),
        new Item(3, "Doohickey", "A thing whose name you can't recall")
    );

    @Value("${RESPONSE_DELAY_MS:0}")
    private long responseDelayMs;

    @GetMapping
    public List<Item> list() throws InterruptedException {
        if (responseDelayMs > 0) Thread.sleep(responseDelayMs);
        return ITEMS;
    }

    @GetMapping("/{id}")
    public ResponseEntity<Item> get(@PathVariable int id) {
        return ITEMS.stream()
            .filter(item -> item.id() == id)
            .findFirst()
            .map(ResponseEntity::ok)
            .orElse(ResponseEntity.notFound().build());
    }
}
