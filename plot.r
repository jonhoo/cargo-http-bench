library(ggplot2)

t <- read.table('timings.dat', header=TRUE)

# fix up units
t$speed <- gsub("k$", "", t$speed)
t <- transform(t, speed = as.numeric(speed))
t$speed <- t$speed * 1000 * 2 * 8 # bps
t$speed <- t$speed / 1000.0 / 1000.0 # Mbps

# use a good order
t$implementation <- factor(t$implementation, levels = c("git", "http", "http-changelog", "http-cloudfront", "dont-use-stale", "use-stale"))
t$project <- factor(t$project, levels = c("empty", "one-dep", "cargo-like", "ripgrep", "inferno", "actix", "brotli2", "bytes", "handlebars", "hyper", "hyper-rusttls", "nom", "quick-xml", "tar", "tokio", "warp", "rand"))
t$metric <- factor(t$metric, levels = c("fresh", "fresh-locked", "rerun", "rerun-locked", "rerun-no-upd", "incr-locked", "update-locked"))
t$speed <- factor(t$speed)
levels(t$speed) <- c("CDN", "5Mbps", "20Mbps")
t$rate <- factor(t$rate)
# levels(t$rate) <- c("17rps", "150rps")
levels(t$rate) <- c("CDN", "150rps")
t$depth <- factor(t$depth)

d <- t[t$speed == "CDN" & t$rate == "CDN",]
p <- ggplot(d, aes(metric, time, fill = metric))
p <- p + theme(axis.text.x = element_blank())
p <- p + scale_fill_brewer(palette = "Paired")
p <- p + geom_col()
p <- p + ylim(0, 5)
p <- p + facet_grid(project ~ implementation)
p <- p + ylab("Time (s)")
p <- p + labs(fill = "Operation")
p <- p + ggtitle("Against CloudFront; stale index file optimization")
ggsave(filename = "cdn.pdf", plot = p, width=5, height=20)
ggsave(filename = "cdn.png", plot = p, width=5, height=20)

quit()

d <- t[t$speed == "20Mbps" & t$rate == "150rps",]
p <- ggplot(d, aes(metric, time, fill = metric))
p <- p + theme(axis.text.x = element_blank())
p <- p + scale_fill_brewer(palette = "Paired")
p <- p + geom_col()
p <- p + facet_grid(project ~ implementation)
p <- p + ylab("Time (s)")
p <- p + labs(fill = "Operation")
p <- p + ggtitle("Sparse HTTP-based registry API evaluation @ 20Mbps / 30rps")
ggsave(filename = "comp.pdf", plot = p, width=5, height=20)
ggsave(filename = "comp.png", plot = p, width=5, height=20)

d <- t[t$project == "cargo-like" & t$metric == "fresh-locked",]
p <- ggplot(d, aes(implementation, time, fill = implementation))
p <- p + theme(axis.text.x = element_blank())
p <- p + scale_fill_brewer(palette = "Dark2")
p <- p + geom_col()
p <- p + facet_grid(speed ~ rate)
p <- p + ylab("Time (s)")
p <- p + labs(fill = "Implementation")
p <- p + ggtitle("Sparse HTTP-based registry API evaluation: cargo-like fresh-locked")
ggsave(filename = "network-cargo-like.pdf", plot = p, width=10, height=10)
ggsave(filename = "network-cargo-like.png", plot = p, width=10, height=10)

d <- t[t$implementation == "http" & t$metric == "fresh-locked",]
p <- ggplot(d, aes(size, time, color = depth, size = depth))
p <- p + scale_colour_brewer()
p <- p + geom_point()
p <- p + facet_wrap(. ~ rate)
p <- p + xlab("# dependencies (transitive)")
p <- p + ylab("Time (s)")
p <- p + labs(color = "Depth", size = "Depth")
p <- p + ggtitle("Sparse HTTP-based registry API evaluation: http fresh-locked by dependency counts")
ggsave(filename = "closure.pdf", plot = p, width=10, height=4)
ggsave(filename = "closure.png", plot = p, width=10, height=4)
