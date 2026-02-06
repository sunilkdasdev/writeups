
**Result:** all time‑outs, leak detection, and house‑keeping now rely on a **steady** source, eliminating the “Retrograde clock change detected” warning even when the OS clock jumps.

> **Tip:** In Spring Boot you can expose the `DataSource` bean with the same configuration, or set the property `spring.datasource.hikari.clock=your.package.MonotonicClock` if you register it as a Spring bean.

---  

## 6. Operating Without Internet Access  

When a server cannot reach external NTP servers (air‑gapped, protected environment), you still need a reliable time source.

| Strategy | How to implement |
|----------|-----------------|
| **Local NTP server** | Deploy a simple **chronyd** instance on a trusted machine that has a manually calibrated clock (via GPS, atomic clock, or periodic admin sync). All hosts point to its IP (`server <local‑ntp‑ip>`). |
| **Hardware clock discipline** | Use a **GPS‑disciplined oscillator** or a **dedicated time appliance** that provides NTP on the LAN. |
| **Offline mode with RTC** | Configure the OS’s NTP client to fall back to the hardware RTC (`FallbackNTP=rtc` in `systemd-timesyncd.conf`). Accept a modest drift (seconds per day) and correct it manually on a regular schedule. |
| **Monotonic clock for internal calculations** | As described above, inject a monotonic clock so Java components stay immune to the drift. |
| **Periodic manual sync** | Create a cron job that runs once a week (or month) and executes `chronyc -a makestep` *only if* the network is available. If the network is down, the job does nothing, leaving the clock unchanged. |

---  

## 7. Best‑Practice Checklist  

| ✅ Item | Action |
|--------|--------|
| **Set system timezone to UTC** | `timedatectl set-timezone UTC` |
| **Run a reliable NTP daemon** | `chronyd` is preferred; ensure `makestep 0 0` (slew‑only). |
| **Configure a local NTP source** | Deploy a LAN‑only NTP server or use a router with NTP. |
| **Upgrade HikariCP ≥ 4.0.3** | Get the built‑in `Clock` support. |
| **Inject a monotonic clock** | `config.setClock(new MonotonicClock());` |
| **Disable VM time‑sync if using NTP inside guest** | Turn off “Synchronize guest time with host” in hypervisor settings. |
| **Monitor NTP status** | `systemctl status chronyd` / `w32tm /query /status`. |
| **Alert on HikariCP retrograde warnings** | Add a log‑stash/ELK rule to capture “Retrograde clock change detected”. |
| **Plan for offline operation** | Keep a local NTP, or schedule periodic manual clock corrections. |
| **Document the time‑sync architecture** | Include the NTP topology, fallback policies, and the monotonic‑clock injection in your run‑books. |

---  

## 8. References & Further Reading  

| Source | Link |
|--------|------|
| HikariCP documentation – Clock API | <https://github.com/brettwooldridge/HikariCP#clock> |
| systemd‑timesyncd manual | <https://www.freedesktop.org/software/systemd/man/systemd-timesyncd.service.html> |
| chrony – high‑performance NTP client/server | <https://chrony.tuxfamily.org/> |
| NTP “step vs slew” explanation | <https://en.wikipedia.org/wiki/Network_Time_Protocol#Clock_steering> |
| Java monotonic time (`System.nanoTime`) | <https://docs.oracle.com/javase/8/docs/api/java/lang/System.html#nanoTime--> |
| Handling time‑skew in distributed systems | <https://martinfowler.com/articles/time-skew.html> |
| Docker & VM time‑sync pitfalls | <https://docs.docker.com/config/containers/runmetrics/#time-synchronization> |

---  

*Prepared for developers and operations teams dealing with time‑related anomalies in Java micro‑service environments.*
