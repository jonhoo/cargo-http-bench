#!/bin/bash
cargo="$1"
timings="$PWD/timings.dat"

speed=0
rate=0
if [ ! -e "$timings" ]; then
	echo "project depth size implementation metric speed rate time" > "$timings"
fi

for x in */Cargo.toml; do
	if [[ $x = "*/Cargo.toml" ]]; then
		echo "Error: no benchmarks"
		exit 1
	fi
done

function bench() {
	category=$1
	shift
	dir="$1"
	shift
	trace="no"
	tmp="/tmp/cargo-bench-git-$dir"

	# make sure we have a clean starting point
	rm -rf "$tmp" 2>/dev/null

	# isolate cargo
	# export "CARGO_LOG=debug"
	export "CARGO_HOME=$tmp"
	export "CARGO_TARGET_DIR=$PWD/target"
	export "RUST_BACKTRACE=1"

	function maybe_trace() {
		uniq=$1
		shift
		f=~/Desktop/cargo-prefetch-$dir-$uniq.trace
		rm -rf "$f"
		if [[ $trace = "yes" ]]; then
			xcrun xctrace record --template "Time Profiler" --output "$f" --target-stdout - --launch -- "$cargo" -Zhttp-registry --color always "$@"
		else
			"$cargo" -Zhttp-registry "$@"
		fi
	}

	function run() {
		metric=$1
		# use start/end, not time, to avoid capturing output
		# which tends to mess up detection of terminal and such
		start=$(gdate +%s.%N)
		maybe_trace "$@" > /dev/null
		end=$(gdate +%s.%N)
		took=$(echo "$end - $start" | bc -l)
		took_s=$(echo "$took" | sed 's/\..*//')
		if [[ -z $took_s ]]; then
			took_s="0"
		fi
		depth=$(awk '{print $1}' .dep-meta)
		size=$(awk '{print $2}' .dep-meta)
		echo "$dir $depth $size $category $metric $speed $rate $took" >> "$timings"
		if ((took_s > 60)); then
			min=$((took_s / 60))
			sec=$(echo "$took - $min * 60.0" | bc -l)
			echo " .. took: ${min}m ${sec}s"
		else
			echo "took: ${took}s"
		fi
	}

	pushd "$dir" >/dev/null

	# remove the injected dependency if it was there
	sed -i .bpk '/^blank /d' Cargo.toml

	rm -f Cargo.lock > /dev/null
	echo " -> pull & discard to warm intermediate caches"
	"$cargo" -Zhttp-registry "$@" update -p stub
	rm -rf "$tmp"
	echo " -> fresh build"
	run fresh "$@" update -p stub
	echo " -> fresh build with lockfile"
	rm -rf "$tmp"
	run fresh-locked "$@" update -p stub
	echo " -> rebuild with lockfile"
	run rerun-locked "$@" update -p stub
	echo " -> rebuild"
	rm Cargo.lock
	run rerun "$@" update -p stub
	echo " -> rebuild w/o update"
	rm Cargo.lock
	run rerun-no-upd "$@" -Zno-index-update update -p stub
	echo " -> update with lockfile"
	run update-locked "$@" update
	echo " -> add blank with lockfile"
	echo "blank = '0.1'" >> Cargo.toml
	run incr-locked "$@" update -p stub
	popd >/dev/null

	# and clean up
	rm -rf "$tmp" 2>/dev/null
}

# first, we figure out the depth + size of each crate's dependency graph
echo ":: tree inspection time"
for ct in */Cargo.toml; do
	echo "==> skipping for now"
	break

	dir=$(dirname "$ct")
	[[ $dir != "stub" ]] || continue
	echo "==> $dir"

	# use standard cargo here
	rm -r "$dir/.cargo" 2>/dev/null

	pushd "$dir" > /dev/null
	depth=$(cargo tree | sed 's/[^│]//g' | sed 's/./x/g' | perl -ne 'print(length($_), "\n")' | awk 'BEGIN { depth = 0; } { if ($1 > depth) { depth = $1 }
} END {print depth}')
	size=$(cargo tree | sed 's/.*─ //g' | grep ' v' | sed 's/ (.*)$//' | sort | uniq | wc -l)
	echo "$depth $size" > .dep-meta
	popd > /dev/null
done

echo
echo ":: CloudFlare HTTP-based registry benchmarks"

speed=0
rate=0

# then, benchmark each against CloudFront
for ct in */Cargo.toml; do
	dir=$(dirname "$ct")
	[[ $dir != "stub" ]] || continue
	echo "==> $dir"

	# make crates-io use our local checkout
	rm -r "$dir/.cargo" 2>/dev/null
	mkdir -p "$dir/.cargo"
	cat > "$dir/.cargo/config.toml" <<EOF
[source.crates-io]
registry = 'https://wut'
replace-with = 'the-http-one'

[source.the-http-one]
registry = 'sparse+https://crates-io-index-temp.rust-lang.org/6887cde41199f4e2934e64646c02e76f8061365e/'
EOF

	# and fly!
	bench http-cloudfront "$dir"

	echo " -> breaking after first thing"
done

# then, benchmark each against CloudFlare
for ct in */Cargo.toml; do
	echo "==> skipping CloudFlare for now"
	break;

	dir=$(dirname "$ct")
	[[ $dir != "stub" ]] || continue
	echo "==> $dir"

	# make crates-io use our local checkout
	rm -r "$dir/.cargo" 2>/dev/null
	mkdir -p "$dir/.cargo"
	cat > "$dir/.cargo/config.toml" <<EOF
[source.crates-io]
registry = 'https://wut'
replace-with = 'the-http-one'

[source.the-http-one]
registry = 'sparse+https://lib.rs/registry-proxy/'
EOF

	# and fly!
	bench http-cloudflare "$dir"
done

for s in 625k 1250k; do
	echo "==> skipping local benchmarks for now"
	break

	speed=$s
	for r in 17 150; do
		rate=$r

		echo " === ${s}Bps @ ${r}r/s =="

		sed -i .bkp "s/limit_rate .*;/limit_rate $s;/" /usr/local/etc/nginx/nginx.conf
		sed -i .bkp "/limit_req_zone/ s/rate=[0-9]*r/rate=${r}r/" /usr/local/etc/nginx/nginx.conf
		nginx -s reload
		# give it time
		sleep 1

		if [[ $r = 150 ]]; then
			echo
			echo ":: git-based registry benchmarks"

			# then, benchmark each with standard API
			for ct in */Cargo.toml; do
				dir=$(dirname "$ct")
				[[ $dir != "stub" ]] || continue

				# we only care about checking git for one
				# "big" project -- all the others will look
				# the same.
				if [[ $dir = "empty" || $dir = "one-dep" || $dir = "cargo-like" ]]; then
					:
				else
					continue
				fi
				echo "==> $dir"

				# make crates-io use our local checkout
				rm -r "$dir/.cargo" 2>/dev/null
				mkdir -p "$dir/.cargo"
				cat > "$dir/.cargo/config.toml" <<EOF
[source.crates-io]
registry = 'https://wut'
replace-with = 'the-http-one'

[source.the-http-one]
registry = 'http://localhost:8080/git/'
EOF

				# and fly!
				bench git "$dir"
			done
		fi

		if [[ $s = 1250k && $r != 17 ]]; then
			echo
			echo ":: http-based registry benchmarks (no changelog)"

			# then, rewire all to use HTTP API and bench again
			for ct in */Cargo.toml; do
				dir=$(dirname "$ct")
				[[ $dir != "stub" ]] || continue
				echo "==> $dir"

				# make crates-io use HTTP API
				rm -r "$dir/.cargo" 2>/dev/null
				mkdir -p "$dir/.cargo"
				cat > "$dir/.cargo/config.toml" <<EOF
[source.crates-io]
registry = 'https://wut'
replace-with = 'the-http-one'

[source.the-http-one]
registry = 'sparse+http://localhost:8080/'
EOF

				# and fly!
				bench http "$dir"
			done

			echo
			echo ":: http-based registry benchmarks (empty changelog)"

			# finally, run again with -Z assume-empty-changelog
			for ct in */Cargo.toml; do
				echo "==> skipping"
				break
				dir=$(dirname "$ct")
				[[ $dir != "stub" ]] || continue
				echo "==> $dir"

				# make crates-io use HTTP API
				rm -r "$dir/.cargo" 2>/dev/null
				mkdir -p "$dir/.cargo"
				cat > "$dir/.cargo/config.toml" <<EOF
[source.crates-io]
registry = 'https://wut'
replace-with = 'the-http-one'

[source.the-http-one]
registry = 'sparse+http://localhost:8080/'
EOF

				# and fly!
				bench http-changelog "$dir" -Z assume-empty-changelog
			done
		fi
	done
done
