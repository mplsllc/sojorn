// Copyright (c) 2026 MPLS LLC
// Licensed under the Business Source License 1.1
// See LICENSE file for details

package repository

import (
	"context"
	"regexp"
	"testing"

	"github.com/pashagolub/pgxmock/v4"
)

func TestGetEnabledCategoryIDs(t *testing.T) {
	mock, err := pgxmock.NewPool()
	if err != nil {
		t.Fatalf("an error '%s' was not expected when opening a stub database connection", err)
	}
	defer mock.Close()

	repo := NewCategoryRepository(mock)
	ctx := context.Background()
	userID := "user-123"

	t.Run("Returns enabled categories when selections exist", func(t *testing.T) {
		rows := pgxmock.NewRows([]string{"category_id"}).
			AddRow("cat-1").
			AddRow("cat-2")

		mock.ExpectQuery(regexp.QuoteMeta(`SELECT category_id FROM public.user_category_settings`)).
			WithArgs(userID).
			WillReturnRows(rows)

		ids, err := repo.GetEnabledCategoryIDs(ctx, userID)
		if err != nil {
			t.Errorf("error was not expected while getting stats: %s", err)
		}

		if len(ids) != 2 {
			t.Errorf("expected 2 ids, got %d", len(ids))
		}
		if ids[0] != "cat-1" {
			t.Errorf("expected cat-1, got %s", ids[0])
		}
	})

	t.Run("Returns ALL active categories when no selections exist (Failsafe)", func(t *testing.T) {
		// First query returns empty
		mock.ExpectQuery(regexp.QuoteMeta(`SELECT category_id FROM public.user_category_settings`)).
			WithArgs(userID).
			WillReturnRows(pgxmock.NewRows([]string{"category_id"})) // Empty

		// Fallback query returns all active
		fallbackRows := pgxmock.NewRows([]string{"id"}).
			AddRow("cat-active-1").
			AddRow("cat-active-2").
			AddRow("cat-active-3")

		mock.ExpectQuery(regexp.QuoteMeta(`SELECT id FROM public.categories WHERE is_active = true`)).
			WillReturnRows(fallbackRows)

		ids, err := repo.GetEnabledCategoryIDs(ctx, userID)
		if err != nil {
			t.Errorf("error was not expected: %s", err)
		}

		if len(ids) != 3 {
			t.Errorf("expected 3 fallback ids, got %d", len(ids))
		}
		if ids[0] != "cat-active-1" {
			t.Errorf("expected cat-active-1, got %s", ids[0])
		}
	})
}
