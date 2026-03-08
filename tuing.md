┌─────────────────────┐
│   PROBLEM DETECTED  │
└──────────┬──────────┘
           ↓
┌─────────────────────────────────┐
│ App frozen / not responding?     │
├─────────────────────────────────┤
│ Yes → jstack (thread dump)       │
│        Look for BLOCKED/DEADLOCK │
│ No  → Continue                    │
└─────────────────────────────────┘
           ↓
┌─────────────────────────────────┐
│ High CPU usage?                  │
├─────────────────────────────────┤
│ Yes → top -H (find thread)       │
│       jstack (convert to hex)    │
│       Find RUNNABLE in same code │
│ No  → Continue                    │
└─────────────────────────────────┘
           ↓
┌─────────────────────────────────┐
│ Memory growing / OOM?            │
├─────────────────────────────────┤
│ Yes → jstat -gcutil (check GC)   │
│       jmap -histo (quick check)  │
│       jmap -dump (full analysis) │
│ No  → Continue                    │
└─────────────────────────────────┘
           ↓
┌─────────────────────────────────┐
│ Slow but not dying?              │
├─────────────────────────────────┤
│ Yes → jstat -gccause (GC cause)  │
│       jcmd JFR.start (profile)   │
│       jvisualvm (deep profiling) │
└─────────────────────────────────┘
