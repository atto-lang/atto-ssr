package dev.oreslang.runtime;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.Timeout;

import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.atomic.AtomicInteger;

import static org.junit.jupiter.api.Assertions.*;

@Timeout(15)
final class ActorEndCleanupTest {

    @Test
    void cleanupRunsOnceAfterCurrentReceiveAndQueuedMailNeverFires() {
        try (ActorRuntime runtime = new ActorRuntime()) {
            List<String> events =
                    java.util.Collections.synchronizedList(new ArrayList<>());
            AtomicInteger receives = new AtomicInteger();

            ActorRuntime.ActorRef<String> ref = runtime.spawnSharedTrusted(
                    context -> (message, turn) -> {
                        int receive = receives.incrementAndGet();
                        events.add("receive-" + receive + ":" + message);

                        // Deterministically queue another mailbox item before
                        // requesting end. self.end must discard it.
                        turn.self().send("queued-second");

                        turn.runtime().endCurrentActorWithCleanup(
                                () -> events.add("cleanup"));
                        events.add("after-end-request");
                    });

            ref.ready().join();
            ref.send("first");
            ref.done().join();

            assertEquals(1, receives.get(),
                    "no receive may start after self.end seals the mailbox");
            assertEquals(
                    List.of(
                            "receive-1:first",
                            "after-end-request",
                            "cleanup"),
                    events,
                    "cleanup must be the final actor-local action");
        }
    }

    @Test
    void outputRemainsAvailableUntilFinalCleanupCompletes() {
        try (ActorRuntime runtime = new ActorRuntime()) {
            ActorRuntime.ActorRef<String> ref = runtime.spawnSharedTrusted(
                    context -> (message, turn) -> {
                        turn.runtime().emitCurrentActorOutput("before");
                        turn.runtime().endCurrentActorWithCleanup(
                                () -> turn.runtime().emitCurrentActorOutput("cleanup"));
                        turn.runtime().emitCurrentActorOutput("after");
                    });

            ref.ready().join();
            ref.send("go");

            var first = ref.outputs().next().join();
            var second = ref.outputs().next().join();
            var third = ref.outputs().next().join();
            ref.done().join();
            var terminal = ref.outputs().next().join();

            assertEquals("before", first.value().value());
            assertEquals("after", second.value().value());
            assertEquals("cleanup", third.value().value());
            assertEquals(0L, first.value().sequence());
            assertEquals(1L, second.value().sequence());
            assertEquals(2L, third.value().sequence());
            assertTrue(terminal.done());
        }
    }

    @Test
    void repeatedEndCannotReplaceTheRegisteredCleanup() {
        try (ActorRuntime runtime = new ActorRuntime()) {
            AtomicInteger cleanups = new AtomicInteger();
            ActorRuntime.ActorRef<String> ref = runtime.spawnSharedTrusted(
                    context -> (message, turn) -> {
                        turn.runtime().endCurrentActorWithCleanup(cleanups::incrementAndGet);
                        assertThrows(
                                IllegalStateException.class,
                                () -> turn.runtime().endCurrentActorWithCleanup(
                                        () -> cleanups.addAndGet(100)));
                    });

            ref.ready().join();
            ref.send("go");
            ref.done().join();
            assertEquals(1, cleanups.get());
        }
    }

    @Test
    void cleanupFailureMakesDoneExceptionalButStillFinalizesActor() {
        try (ActorRuntime runtime = new ActorRuntime()) {
            ActorRuntime.ActorRef<String> ref = runtime.spawnSharedTrusted(
                    context -> (message, turn) ->
                            turn.runtime().endCurrentActorWithCleanup(
                                    () -> {
                                        throw new IllegalStateException(
                                                "cleanup failed");
                                    }));

            ref.ready().join();
            ref.send("go");

            java.util.concurrent.CompletionException failed =
                    assertThrows(
                            java.util.concurrent.CompletionException.class,
                            () -> ref.done().join());
            assertEquals("cleanup failed", failed.getCause().getMessage());
            assertFalse(ref.isAlive());
            assertEquals(
                    "cleanup failed",
                    ref.failure().orElseThrow().getMessage());
        }
    }
}
