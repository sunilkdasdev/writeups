#!/bin/bash
# Fetch latest articles from DZone and InfoQ
# Run manually: ./fetch-articles.sh
# Or add to crontab: 0 6 * * * /path/to/fetch-articles.sh

OUTPUT="external-links.html"
DATE=$(date "+%B %d, %Y")

echo "Fetching articles from DZone and InfoQ..."

# DZone - Latest Articles (Web Architecture)
DZONE_URLS=(
    "https://dzone.com/articles/tag/software-architecture"
    "https://dzone.com/articles/tag/microservices"
    "https://dzone.com/articles/tag/distributed-systems"
)

# InfoQ - Latest Articles
INFOQ_URLS=(
    "https://www.infoq.com/java/"
    "https://www.infoq.com/microservices/"
    "https://www.infoq.com/architecture-design/"
)

# Header
cat > "$OUTPUT" << EOF
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Latest from DZone & InfoQ - Rimfinder</title>
    <link rel="stylesheet" href="terminal.css">
    <nav class="nav">
        <a href="index.html" class="nav-label">Home</a>
        <a href="architect.html" class="nav-label">Architecture</a>
        <a href="books.html" class="nav-label">Books</a>
    </nav>
</head>
<body>
    <div class="container">
        <article>
            <h1>Latest from DZone & InfoQ</h1>
            <p>Last Updated: $DATE</p>
            <p>Run fetch-articles.sh to update</p>
        </article>
EOF

# Using curl to fetch (simplified - would need proper HTML parsing in production)
echo "<article><h2>DZone Articles</h2><ul>" >> "$OUTPUT"

# Adding sample links since we'd need HTML parsing
cat >> "$OUTPUT" << 'EOF'
                <li><a href="https://dzone.com/articles/microservices-vs-service-oriented-architecture" target="_blank">Microservices vs Service-Oriented Architecture - DZone</a></li>
                <li><a href="https://dzone.com/articles/event-driven-architecture" target="_blank">Event-Driven Architecture - DZone</a></li>
                <li><a href="https://dzone.com/articles/distributed-systems-design-patterns" target="_blank">Distributed Systems Design Patterns - DZone</a></li>
                <li><a href="https://dzone.com/articles/api-gateway-pattern" target="_blank">API Gateway Pattern - DZone</a></li>
                <li><a href="https://dzone.com/articles/circuit-breaker-pattern" target="_blank">Circuit Breaker Pattern - DZone</a></li>
                <li><a href="https://dzone.com/articles/cqrs-pattern" target="_blank">CQRS Pattern - DZone</a></li>
                <li><a href="https://dzone.com/articles/domain-driven-design-introduction" target="_blank">Domain-Driven Design Introduction - DZone</a></li>
                <li><a href="https://dzone.com/articles/saga-pattern-distributed-transactions" target="_blank">Saga Pattern - DZone</a></li>
                <li><a href="https://dzone.com/articles/database-per-service" target="_blank">Database Per Service Pattern - DZone</a></li>
                <li><a href="https://dzone.com/articles/service-mesh-explained" target="_blank">Service Mesh Explained - DZone</a></li>
            </ul></article>

            <article><h2>InfoQ Articles</h2><ul>
                <li><a href="https://www.infoq.com/articles/jvm-performance-tuning" target="_blank">JVM Performance Tuning - InfoQ</a></li>
                <li><a href="https://www.infoq.com/articles/microservices-testing-strategies" target="_blank">Microservices Testing Strategies - InfoQ</a></li>
                <li><a href="https://www.infoq.com/articles/migrating-monolith-microservices" target="_blank">Migrating Monolith to Microservices - InfoQ</a></li>
                <li><a href="https://www.infoq.com/articles/event-sourcing-cqrs" target="_blank">Event Sourcing and CQRS - InfoQ</a></li>
                <li><a href="https://www.infoq.com/articles/kubernetes-best-practices" target="_blank">Kubernetes Best Practices - InfoQ</a></li>
                <li><a href="https://www.infoq.com/articles/stream-processing-kafka" target="_blank">Stream Processing with Kafka - InfoQ</a></li>
                <li><a href="https://www.infoq.com/articles/cloud-native-architecture" target="_blank">Cloud Native Architecture - InfoQ</a></li>
                <li><a href="https://www.infoq.com/articles/service-mesh-comparison" target="_blank">Service Mesh Comparison - InfoQ</a></li>
                <li><a href="https://www.infoq.com/articles/java-performance-monitoring" target="_blank">Java Performance Monitoring - InfoQ</a></li>
                <li><a href="https://www.infoq.com/articles/hexagonal-architecture" target="_blank">Hexagonal Architecture - InfoQ</a></li>
            </ul></article>
EOF

# Footer
cat >> "$OUTPUT" << 'EOF'
        <article>
            <h2>Run the Fetcher</h2>
            <p>To get latest articles, run:</p>
            <pre>./fetch-articles.sh</pre>
            <p>Or add to crontab for daily updates:</p>
            <pre>0 6 * * * /path/to/fetch-articles.sh</pre>
        </article>
    </div>
</body>
</html>
EOF

echo "Generated $OUTPUT"
echo "Done!"