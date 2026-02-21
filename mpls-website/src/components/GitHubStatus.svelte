<script lang="ts">
	import { onMount } from 'svelte';
	import { GitCommit } from 'lucide-svelte';

	export let repoUrl: string;

	let status = 'Checking deploy...';

	const parseRepo = (url: string): { owner: string; repo: string } | null => {
		try {
			const parsed = new URL(url);
			const [, owner, repo] = parsed.pathname.split('/');
			if (!owner || !repo) return null;
			return { owner, repo };
		} catch {
			return null;
		}
	};

	const timeAgo = (date: Date): string => {
		const seconds = Math.floor((Date.now() - date.getTime()) / 1000);
		const ranges: [number, string][] = [
			[60, 'second'],
			[60, 'minute'],
			[24, 'hour'],
			[7, 'day'],
			[4.34524, 'week'],
			[12, 'month'],
		];

		let count = seconds;
		let unit = 'second';

		for (const [limit, label] of ranges) {
			if (count < limit) {
				unit = label;
				break;
			}
			count = Math.floor(count / limit);
			unit = label;
		}

		if (count <= 0) return 'just now';
		return `${count} ${unit}${count !== 1 ? 's' : ''}`;
	};

	onMount(async () => {
		const parsed = repoUrl ? parseRepo(repoUrl) : null;
		if (!parsed) {
			status = 'Last deploy: unavailable';
			return;
		}

		try {
			const response = await fetch(
				`https://api.github.com/repos/${parsed.owner}/${parsed.repo}/commits?per_page=1`,
				{
					headers: {
						Accept: 'application/vnd.github+json',
					},
				},
			);

			if (!response.ok) {
				status = 'Last deploy: unavailable';
				return;
			}

			const data = await response.json();
			const latest = data?.[0]?.commit?.committer?.date;

			if (!latest) {
				status = 'Last deploy: unavailable';
				return;
			}

			status = `Last deploy: ${timeAgo(new Date(latest))} ago`;
		} catch {
			status = 'Last deploy: unavailable';
		}
	});
</script>

<div class="flex items-center justify-center gap-2 text-xs font-mono uppercase tracking-[0.2em] text-white/50">
	<GitCommit class="h-4 w-4 text-white/60" />
	<span>{status}</span>
</div>
