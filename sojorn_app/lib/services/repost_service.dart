import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sojorn/models/repost.dart';
import 'package:sojorn/models/post.dart';
import 'package:sojorn/services/api_service.dart';
import 'package:sojorn/providers/api_provider.dart';

class RepostService {
  static const String _repostsCacheKey = 'reposts_cache';
  static const String _amplificationCacheKey = 'amplification_cache';
  static const Duration _cacheExpiry = Duration(minutes: 5);

  /// Create a new repost
  Future<Repost?> createRepost({
    required String originalPostId,
    required RepostType type,
    String? comment,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      final response = await ApiService.instance.post('/posts/repost', {
        'original_post_id': originalPostId,
        'type': type.name,
        'comment': comment,
        'metadata': metadata,
      });

      if (response['success'] == true) {
        return Repost.fromJson(response['repost']);
      }
    } catch (e) {
      print('Error creating repost: $e');
    }
    return null;
  }

  /// Boost a post (amplify its reach)
  Future<bool> boostPost({
    required String postId,
    required RepostType boostType,
    int? boostAmount,
  }) async {
    try {
      final response = await ApiService.instance.post('/posts/boost', {
        'post_id': postId,
        'boost_type': boostType.name,
        'boost_amount': boostAmount ?? 1,
      });

      return response['success'] == true;
    } catch (e) {
      print('Error boosting post: $e');
      return false;
    }
  }

  /// Get all reposts for a post
  Future<List<Repost>> getRepostsForPost(String postId) async {
    try {
      final response = await ApiService.instance.get('/posts/$postId/reposts');
      
      if (response['success'] == true) {
        final repostsData = response['reposts'] as List<dynamic>? ?? [];
        return repostsData.map((r) => Repost.fromJson(r as Map<String, dynamic>)).toList();
      }
    } catch (e) {
      print('Error getting reposts: $e');
    }
    return [];
  }

  /// Get user's repost history
  Future<List<Repost>> getUserReposts(String userId, {int limit = 20}) async {
    try {
      final response = await ApiService.instance.get('/users/$userId/reposts?limit=$limit');
      
      if (response['success'] == true) {
        final repostsData = response['reposts'] as List<dynamic>? ?? [];
        return repostsData.map((r) => Repost.fromJson(r as Map<String, dynamic>)).toList();
      }
    } catch (e) {
      print('Error getting user reposts: $e');
    }
    return [];
  }

  /// Delete a repost
  Future<bool> deleteRepost(String repostId) async {
    try {
      final response = await ApiService.instance.delete('/reposts/$repostId');
      return response['success'] == true;
    } catch (e) {
      print('Error deleting repost: $e');
      return false;
    }
  }

  /// Get amplification analytics for a post
  Future<AmplificationAnalytics?> getAmplificationAnalytics(String postId) async {
    try {
      final response = await ApiService.instance.get('/posts/$postId/amplification');
      
      if (response['success'] == true) {
        return AmplificationAnalytics.fromJson(response['analytics']);
      }
    } catch (e) {
      print('Error getting amplification analytics: $e');
    }
    return null;
  }

  /// Get trending posts based on amplification
  Future<List<Post>> getTrendingPosts({int limit = 10, String? category}) async {
    try {
      String url = '/posts/trending?limit=$limit';
      if (category != null) {
        url += '&category=$category';
      }
      
      final response = await ApiService.instance.get(url);
      
      if (response['success'] == true) {
        final postsData = response['posts'] as List<dynamic>? ?? [];
        return postsData.map((p) => Post.fromJson(p as Map<String, dynamic>)).toList();
      }
    } catch (e) {
      print('Error getting trending posts: $e');
    }
    return [];
  }

  /// Get amplification rules
  Future<List<FeedAmplificationRule>> getAmplificationRules() async {
    try {
      final response = await ApiService.instance.get('/amplification/rules');
      
      if (response['success'] == true) {
        final rulesData = response['rules'] as List<dynamic>? ?? [];
        return rulesData.map((r) => FeedAmplificationRule.fromJson(r as Map<String, dynamic>)).toList();
      }
    } catch (e) {
      print('Error getting amplification rules: $e');
    }
    return [];
  }

  /// Calculate amplification score for a post
  Future<int> calculateAmplificationScore(String postId) async {
    try {
      final response = await ApiService.instance.post('/posts/$postId/calculate-score', {});
      
      if (response['success'] == true) {
        return response['score'] as int? ?? 0;
      }
    } catch (e) {
      print('Error calculating amplification score: $e');
    }
    return 0;
  }

  /// Check if user can boost a post
  Future<bool> canBoostPost(String userId, String postId, RepostType boostType) async {
    try {
      final response = await ApiService.instance.get('/users/$userId/can-boost/$postId?type=${boostType.name}');
      
      return response['can_boost'] == true;
    } catch (e) {
      print('Error checking boost eligibility: $e');
      return false;
    }
  }

  /// Get user's daily boost count
  Future<Map<RepostType, int>> getDailyBoostCount(String userId) async {
    try {
      final response = await ApiService.instance.get('/users/$userId/daily-boosts');
      
      if (response['success'] == true) {
        final boostCounts = response['boost_counts'] as Map<String, dynamic>? ?? {};
        final result = <RepostType, int>{};
        
        boostCounts.forEach((type, count) {
          final repostType = RepostType.fromString(type);
          result[repostType] = count as int;
        });
        
        return result;
      }
    } catch (e) {
      print('Error getting daily boost count: $e');
    }
    return {};
  }

  /// Report inappropriate repost
  Future<bool> reportRepost(String repostId, String reason) async {
    try {
      final response = await ApiService.instance.post('/reposts/$repostId/report', {
        'reason': reason,
      });
      
      return response['success'] == true;
    } catch (e) {
      print('Error reporting repost: $e');
      return false;
    }
  }
}

// Riverpod providers
final repostServiceProvider = Provider<RepostService>((ref) {
  return RepostService();
});

final repostsProvider = FutureProvider.family<List<Repost>, String>((ref, postId) {
  final service = ref.watch(repostServiceProvider);
  return service.getRepostsForPost(postId);
});

final amplificationAnalyticsProvider = FutureProvider.family<AmplificationAnalytics?, String>((ref, postId) {
  final service = ref.watch(repostServiceProvider);
  return service.getAmplificationAnalytics(postId);
});

final trendingPostsProvider = FutureProvider.family<List<Post>, Map<String, dynamic>>((ref, params) {
  final service = ref.watch(repostServiceProvider);
  final limit = params['limit'] as int? ?? 10;
  final category = params['category'] as String?;
  return service.getTrendingPosts(limit: limit, category: category);
});

class RepostController extends Notifier<RepostState> {
  @override
  RepostState build() => const RepostState();

  RepostService get _service => ref.read(repostServiceProvider);

  Future<void> createRepost({
    required String originalPostId,
    required RepostType type,
    String? comment,
    Map<String, dynamic>? metadata,
  }) async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      final repost = await _service.createRepost(
        originalPostId: originalPostId,
        type: type,
        comment: comment,
        metadata: metadata,
      );

      if (repost != null) {
        state = state.copyWith(
          isLoading: false,
          lastRepost: repost,
          error: null,
        );
      } else {
        state = state.copyWith(
          isLoading: false,
          error: 'Failed to create repost',
        );
      }
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Error creating repost: $e',
      );
    }
  }

  Future<void> boostPost({
    required String postId,
    required RepostType boostType,
    int? boostAmount,
  }) async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      final success = await _service.boostPost(
        postId: postId,
        boostType: boostType,
        boostAmount: boostAmount,
      );

      state = state.copyWith(
        isLoading: false,
        lastBoostSuccess: success,
        error: success ? null : 'Failed to boost post',
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Error boosting post: $e',
      );
    }
  }

  Future<void> deleteRepost(String repostId) async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      final success = await _service.deleteRepost(repostId);

      state = state.copyWith(
        isLoading: false,
        lastDeleteSuccess: success,
        error: success ? null : 'Failed to delete repost',
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Error deleting repost: $e',
      );
    }
  }

  void clearError() {
    state = state.copyWith(error: null);
  }

  void reset() {
    state = const RepostState();
  }
}

class RepostState {
  final bool isLoading;
  final String? error;
  final Repost? lastRepost;
  final bool? lastBoostSuccess;
  final bool? lastDeleteSuccess;

  const RepostState({
    this.isLoading = false,
    this.error,
    this.lastRepost,
    this.lastBoostSuccess,
    this.lastDeleteSuccess,
  });

  RepostState copyWith({
    bool? isLoading,
    String? error,
    Repost? lastRepost,
    bool? lastBoostSuccess,
    bool? lastDeleteSuccess,
  }) {
    return RepostState(
      isLoading: isLoading ?? this.isLoading,
      error: error ?? this.error,
      lastRepost: lastRepost ?? this.lastRepost,
      lastBoostSuccess: lastBoostSuccess ?? this.lastBoostSuccess,
      lastDeleteSuccess: lastDeleteSuccess ?? this.lastDeleteSuccess,
    );
  }
}

final repostControllerProvider = NotifierProvider<RepostController, RepostState>(RepostController.new);
