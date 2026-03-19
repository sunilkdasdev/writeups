Volatile Variables
A write to a volatile variable happens before any subsequent read of that same volatile variable. 
When a thread reads a volatile variable, all variables visible to that thread are refreshed from main memory. 
When a thread writes to a volatile variable, all preceding writes to other variables (volatile or non-volatile) are flushed to main memory before the volatile write. 
This prevents reordering that could break correctness, such as setting a flag before updating data. 
Synchronized Blocks
The beginning of a synchronized block guarantees that all visible variables are re-read from main memory. 
The end of a synchronized block guarantees that all modified variables are written back to main memory before the lock is released. 
This ensures that changes made by one thread are visible to another thread that acquires the same lock. 
