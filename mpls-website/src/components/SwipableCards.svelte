<script lang="ts">
	import { onMount } from 'svelte';
	import { ChevronUp, ChevronDown, Bookmark, Share2, ExternalLink } from 'lucide-svelte';

	let container: HTMLDivElement;
	let currentIndex = $state(0);
	let isTransitioning = $state(false);
	let touchStartY = 0;
	let touchStartX = 0;
	let currentTranslateY = $state(0);
	let isDragging = $state(false);

	// Get total number of cards from slots
	let totalCards = $state(5); // Default to 5, will be updated on mount

	const SWIPE_THRESHOLD = 50; // Minimum pixels to trigger swipe
	const VELOCITY_THRESHOLD = 0.5; // Minimum velocity to trigger swipe
	const MAX_TRANSLATE = 100; // Maximum pixels for visual feedback during drag

	function handleTouchStart(e: TouchEvent) {
		if (isTransitioning) return;
		touchStartY = e.touches[0].clientY;
		touchStartX = e.touches[0].clientX;
		isDragging = true;
	}

	function handleTouchMove(e: TouchEvent) {
		if (!isDragging || isTransitioning) return;

		const currentY = e.touches[0].clientY;
		const currentX = e.touches[0].clientX;
		const deltaY = currentY - touchStartY;
		const deltaX = currentX - touchStartX;

		// Only handle vertical swipes (ignore if horizontal movement is greater)
		if (Math.abs(deltaX) > Math.abs(deltaY)) {
			return;
		}

		// Prevent default scrolling
		e.preventDefault();

		// Apply resistance at boundaries
		let translate = deltaY;
		if ((currentIndex === 0 && deltaY > 0) || (currentIndex === totalCards - 1 && deltaY < 0)) {
			translate = deltaY * 0.3; // Add resistance at boundaries
		}

		// Limit translation for visual feedback
		translate = Math.max(-MAX_TRANSLATE, Math.min(MAX_TRANSLATE, translate));
		currentTranslateY = translate;
	}

	function handleTouchEnd() {
		if (!isDragging) return;
		isDragging = false;

		const deltaY = currentTranslateY;

		// Calculate velocity (pixels per ms)
		const velocity = Math.abs(deltaY) / 300; // Approximate time delta

		// Determine if we should swipe
		if (Math.abs(deltaY) > SWIPE_THRESHOLD || velocity > VELOCITY_THRESHOLD) {
			if (deltaY < 0 && currentIndex < totalCards - 1) {
				// Swipe up - go to next
				goToCard(currentIndex + 1);
			} else if (deltaY > 0 && currentIndex > 0) {
				// Swipe down - go to previous
				goToCard(currentIndex - 1);
			} else {
				// Reset position
				currentTranslateY = 0;
			}
		} else {
			// Reset position
			currentTranslateY = 0;
		}
	}

	function handleWheel(e: WheelEvent) {
		if (isTransitioning) return;

		// Debounce scroll events
		e.preventDefault();

		if (e.deltaY > 30 && currentIndex < totalCards - 1) {
			goToCard(currentIndex + 1);
		} else if (e.deltaY < -30 && currentIndex > 0) {
			goToCard(currentIndex - 1);
		}
	}

	function goToCard(index: number) {
		if (index < 0 || index >= totalCards || isTransitioning) return;

		isTransitioning = true;
		currentIndex = index;
		currentTranslateY = 0;

		// Reset transition lock after animation completes
		setTimeout(() => {
			isTransitioning = false;
		}, 600);
	}

	function handleKeydown(e: KeyboardEvent) {
		if (isTransitioning) return;

		if (e.key === 'ArrowDown' || e.key === 'ArrowRight') {
			e.preventDefault();
			goToCard(currentIndex + 1);
		} else if (e.key === 'ArrowUp' || e.key === 'ArrowLeft') {
			e.preventDefault();
			goToCard(currentIndex - 1);
		}
	}

	function handleBookmark() {
		// Trigger browser's native bookmark dialog
		// Note: Modern browsers block this for security, but we can prompt the user
		const url = window.location.href;
		const title = document.title;

		// Try different browser-specific methods
		if ((window as any).sidebar && (window as any).sidebar.addPanel) {
			// Firefox < 23
			(window as any).sidebar.addPanel(title, url, '');
		} else if ((window as any).external && ('AddFavorite' in (window as any).external)) {
			// IE
			(window as any).external.AddFavorite(url, title);
		} else {
			// Modern browsers - show instruction
			alert('Press ' + (navigator.userAgent.toLowerCase().indexOf('mac') !== -1 ? 'Cmd' : 'Ctrl') + '+D to bookmark this page');
		}
	}

	async function handleShare() {
		const url = window.location.href;

		// Try native Web Share API first (works on mobile and some desktop browsers)
		if (navigator.share) {
			try {
				await navigator.share({
					title: 'mp.ls',
					text: 'Check out this project',
					url: url
				});
			} catch (error) {
				// User cancelled or error occurred
				console.log('Share cancelled or failed:', error);
			}
		} else {
			// Fallback: copy to clipboard with user feedback
			try {
				await navigator.clipboard.writeText(url);
				alert('Link copied to clipboard!');
			} catch (error) {
				// Fallback for older browsers
				const textArea = document.createElement('textarea');
				textArea.value = url;
				textArea.style.position = 'fixed';
				textArea.style.opacity = '0';
				document.body.appendChild(textArea);
				textArea.focus();
				textArea.select();
				try {
					document.execCommand('copy');
					alert('Link copied to clipboard!');
				} catch (err) {
					alert('Failed to copy link. URL: ' + url);
				}
				document.body.removeChild(textArea);
			}
		}
	}

	function handleOpen() {
		if (!container) {
			console.error('Container not ready');
			return;
		}

		// Get the current card element and find the primary "Visit Site" link
		const cards = container.querySelectorAll('[data-card]');

		if (cards.length === 0) {
			console.error('No cards found');
			return;
		}

		const currentCard = cards[currentIndex];

		if (!currentCard) {
			console.error('No card found at index:', currentIndex);
			return;
		}

		// Look for the first link with an http/https URL
		const allLinks = currentCard.querySelectorAll('a[href]');
		console.log('Found links:', allLinks.length);

		// Find first external link (starts with http:// or https://)
		let primaryLink: HTMLAnchorElement | null = null;
		for (let i = 0; i < allLinks.length; i++) {
			const link = allLinks[i] as HTMLAnchorElement;
			if (link.href && (link.href.startsWith('http://') || link.href.startsWith('https://'))) {
				primaryLink = link;
				break;
			}
		}

		if (primaryLink && primaryLink.href) {
			console.log('Opening:', primaryLink.href);
			window.open(primaryLink.href, '_blank', 'noopener,noreferrer');
		} else {
			console.log('No external link found in current card');
			alert('No link available for this card');
		}
	}

	onMount(() => {
		// Count the number of card elements
		const cards = container.querySelectorAll('[data-card]');
		totalCards = cards.length;

		// Add keyboard event listener
		window.addEventListener('keydown', handleKeydown);

		return () => {
			window.removeEventListener('keydown', handleKeydown);
		};
	});
</script>

<div
	class="relative h-full w-full overflow-hidden bg-black"
	bind:this={container}
	ontouchstart={handleTouchStart}
	ontouchmove={handleTouchMove}
	ontouchend={handleTouchEnd}
	onwheel={handleWheel}
	role="region"
	aria-label="Swipable content cards"
>
	<div
		class="absolute left-0 top-0 h-full w-full transition-transform"
		class:duration-0={isDragging}
		class:duration-600={!isDragging}
		class:ease-out={!isDragging}
		style="transform: translateY(calc({-currentIndex * 100}% + {isDragging ? currentTranslateY : 0}px))"
	>
		<slot></slot>
	</div>

	<!-- Navigation Dots - TikTok style (right side) -->
	<div class="pointer-events-none absolute inset-y-0 right-0 z-50 flex items-center">
		<div class="pointer-events-auto flex flex-col gap-3 pr-4">
			{#each Array(totalCards) as _, i}
				<button
					onclick={() => goToCard(i)}
					class="group transition-all duration-300"
					aria-label="Go to card {i + 1}"
				>
					<div
						class="rounded-full transition-all duration-300 group-hover:scale-110"
						class:h-3={currentIndex === i}
						class:w-3={currentIndex === i}
						class:h-2={currentIndex !== i}
						class:w-2={currentIndex !== i}
						class:active-dot={currentIndex === i}
						class:inactive-dot={currentIndex !== i}
					></div>
				</button>
			{/each}
		</div>
	</div>

	<!-- Interaction Buttons - TikTok style (right side, bottom) -->
	<div class="pointer-events-none absolute bottom-6 left-1/2 z-50 flex w-full max-w-[min(100vw,calc(100vh*9/16))] -translate-x-1/2 items-end justify-end">
		<div class="pointer-events-auto flex translate-x-14 flex-col gap-4">
			<!-- Bookmark Button -->
			<button
				onclick={handleBookmark}
				class="group flex flex-col items-center gap-1 transition-transform hover:scale-110 active:scale-95"
				aria-label="Bookmark"
			>
				<div class="flex h-12 w-12 items-center justify-center rounded-full border border-white/30 bg-white/10 backdrop-blur-md transition-all group-hover:bg-white/20">
					<Bookmark class="h-6 w-6 text-white" />
				</div>
			</button>

			<!-- Share Button -->
			<button
				onclick={handleShare}
				class="group flex flex-col items-center gap-1 transition-transform hover:scale-110 active:scale-95"
				aria-label="Share"
			>
				<div class="flex h-12 w-12 items-center justify-center rounded-full border border-white/30 bg-white/10 backdrop-blur-md transition-all group-hover:bg-white/20">
					<Share2 class="h-6 w-6 text-white" />
				</div>
			</button>

			<!-- Open Button -->
			<button
				onclick={handleOpen}
				class="group flex flex-col items-center gap-1 transition-transform hover:scale-110 active:scale-95"
				aria-label="Open"
			>
				<div class="flex h-12 w-12 items-center justify-center rounded-full border border-white/30 bg-white/10 backdrop-blur-md transition-all group-hover:bg-white/20">
					<ExternalLink class="h-6 w-6 text-white" />
				</div>
			</button>
		</div>
	</div>

	<!-- Swipe Hint (appears briefly on load) -->
	{#if currentIndex === 0}
		<div class="pointer-events-none absolute bottom-20 left-1/2 z-40 -translate-x-1/2 animate-bounce">
			<div class="flex flex-col items-center gap-2">
				<ChevronUp class="h-10 w-10 text-white opacity-80 drop-shadow-lg" />
				<p class="text-xs font-mono uppercase tracking-widest text-white drop-shadow-lg">Swipe</p>
			</div>
		</div>
	{/if}
</div>

<style>
	.duration-600 {
		transition-duration: 600ms;
	}

	.duration-0 {
		transition-duration: 0ms;
	}

	.active-dot {
		background-color: white;
		box-shadow: 0 4px 6px -1px rgb(0 0 0 / 0.1), 0 2px 4px -2px rgb(0 0 0 / 0.1);
	}

	.inactive-dot {
		background-color: rgba(255, 255, 255, 0.5);
	}

	.group:hover .active-dot,
	.group:hover .inactive-dot {
		background-color: white;
	}

	@keyframes bounce {
		0%, 100% {
			transform: translateY(0);
		}
		50% {
			transform: translateY(-10px);
		}
	}

	.animate-bounce {
		animation: bounce 2s ease-in-out 3;
		animation-delay: 1s;
	}
</style>
