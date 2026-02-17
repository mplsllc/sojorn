package main

import (
	"database/sql"
	"fmt"
	"log"
	"os"

	_ "github.com/lib/pq"
)

func main() {
	dbURL := os.Getenv("DATABASE_URL")
	if dbURL == "" {
		log.Fatal("DATABASE_URL environment variable is not set")
	}

	db, err := sql.Open("postgres", dbURL)
	if err != nil {
		log.Fatal(err)
	}
	defer db.Close()

	// Get column information for groups table
	rows, err := db.Query(`
		SELECT column_name, data_type 
		FROM information_schema.columns 
		WHERE table_name = 'groups' 
		ORDER BY ordinal_position;
	`)
	if err != nil {
		log.Printf("Error querying columns: %v", err)
		return
	}
	defer rows.Close()

	fmt.Println("📋 Groups table columns:")
	for rows.Next() {
		var columnName, dataType string
		err := rows.Scan(&columnName, &dataType)
		if err != nil {
			log.Printf("Error scanning row: %v", err)
			continue
		}
		fmt.Printf("  - %s (%s)\n", columnName, dataType)
	}

	// Check if there's any data
	var count int
	err = db.QueryRow("SELECT COUNT(*) FROM groups").Scan(&count)
	if err != nil {
		log.Printf("Error counting groups: %v", err)
		return
	}
	fmt.Printf("\n📊 Current groups count: %d\n", count)
}
