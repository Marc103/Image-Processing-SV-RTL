`timescale 1ns/10ps

/**
 * This file contains some very simple wrapper classes for queues which let us communicate between
 * tasks.
 *
 * Basic usage looks like this:
 *
 * TriggerableQueue#(item) the_queue;
 * task producer();
 *     // hook the producer up to the consumer
 *     TriggerableQueueBroadcaster#(item) queue_pusher;
 *     queue_pusher.add_queue(the_queue);
 *     forever begin
 *         item tx_i;
 *         // prepare tx_i
 *
 *         queue_pusher.push(tx_i);
 *     end
 * endtask
 *
 * task consumer();
 *     forever begin
 *         item i;
 *         the_queue.pop(i);
 *         // process i
 *     end
 * endtask
 */

package triggerable_queue_pkg;
    /**
     * Class that manages a queue with an event trigger whenever an item is added or removed.
     */
    class TriggerableQueue #(type T = logic);
        T queue[$];
        event element_added_event;
        event element_removed_event;

        // Inserts an element at the beginning of the queue and triggers the addition event.
        task push(T item);
            queue.push_front(item);
            ->element_added_event;
        endtask

        // Waits until the queue has data, then removes the last element and triggers the removal event.
        task pop(output T item);
            while (queue.size() == 0) @(element_added_event);
            item = queue.pop_back();
            ->element_removed_event;
        endtask

        function automatic logic isempty();
            return (queue.size() == 0);
        endfunction
    endclass

    /**
     * A class that manages multiple TriggerableQueues and can broadcast to all of them.
     */
    class TriggerableQueueBroadcaster #(type T = logic);
        TriggerableQueue#(T) managed_queues[$];

        // Registers a new queue for broadcasting.
        function void add_queue(ref TriggerableQueue#(T) q);
            managed_queues.push_back(q);
        endfunction

        // Pushes an element to the front of all managed queues.
        task automatic push(T item);
            foreach (managed_queues[idx]) begin
                managed_queues[idx].push(item);
            end
        endtask
    endclass
endpackage
