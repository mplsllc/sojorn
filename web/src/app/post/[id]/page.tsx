import { Metadata } from 'next';
import { notFound } from 'next/navigation';
import { api } from '@/lib/api';
import { Nav } from '@/components/Nav';
import PostDetail from './post-detail';

interface PostAuthor {
  id: string;
  handle: string;
  display_name: string;
  avatar_url: string;
}

interface PostMedia {
  id: string;
  url: string;
  type: string;
  alt_text?: string;
  preview_url?: string;
}

interface Post {
  id: string;
  content: string;
  content_html: string;
  author: PostAuthor;
  media: PostMedia[];
  like_count: number;
  reply_count: number;
  repost_count: number;
  liked: boolean;
  reposted: boolean;
  bookmarked: boolean;
  created_at: string;
  edited_at?: string;
  visibility: string;
  parent_id?: string;
  replies: Post[];
}

interface Props {
  params: { id: string };
}

async function getPost(id: string): Promise<Post | null> {
  try {
    return await api.getPost(id);
  } catch {
    return null;
  }
}

export async function generateMetadata({ params }: Props): Promise<Metadata> {
  const post = await getPost(params.id);
  if (!post) {
    return { title: 'Post not found' };
  }

  const authorName = post.author.display_name || `@${post.author.handle}`;
  const contentPreview = post.content.replace(/<[^>]*>/g, '').slice(0, 200);
  const title = `${authorName}: "${contentPreview.slice(0, 60)}${contentPreview.length > 60 ? '...' : ''}"`;
  const images = post.media
    .filter((m) => m.type === 'image')
    .map((m) => ({ url: m.url }));

  return {
    title,
    description: contentPreview,
    openGraph: {
      title,
      description: contentPreview,
      images: images.length > 0 ? images : post.author.avatar_url ? [{ url: post.author.avatar_url }] : [],
      type: 'article',
    },
    twitter: {
      card: images.length > 0 ? 'summary_large_image' : 'summary',
      title,
      description: contentPreview,
      images: images.map((i) => i.url),
    },
  };
}

export default async function PostPage({ params }: Props) {
  const post = await getPost(params.id);

  if (!post) {
    notFound();
  }

  return (
    <div className="min-h-screen bg-gray-50 dark:bg-gray-950">
      <Nav />
      <PostDetail post={post} />
    </div>
  );
}
