package config

import (
	"fmt"
	"log"
	"os"

	"gorm.io/driver/mysql"
	"gorm.io/gorm"
	"gorm.io/gorm/logger"

	"github.com/glebarez/sqlite"
)

type Config struct {
	DBHost     string
	DBPort     string
	DBUser     string
	DBPassword string
	DBName     string
	DBType     string // "sqlite" or "mysql"
}

var DB *gorm.DB

// LoadConfig loads configuration from environment variables
func LoadConfig() *Config {
	dbType := getEnv("DB_TYPE", "mysql") // Default to MySQL
	if dbType == "" {
		dbType = "mysql"
	}

	return &Config{
		DBHost:     getEnv("DB_HOST", "localhost"),
		DBPort:     getEnv("DB_PORT", "3306"),
		DBUser:     getEnv("DB_USER", "root"),
		DBPassword: getEnv("DB_PASSWORD", ""),
		DBName:     getEnv("DB_NAME", "entertok"),
		DBType:     dbType,
	}
}

func getEnv(key, defaultValue string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return defaultValue
}

// ConnectDB connects to the database (MySQL or SQLite)
func ConnectDB(config *Config) *gorm.DB {
	var errDB error

	if config.DBType == "sqlite" {
		// Connect to SQLite using glebarez/sqlite (no CGO required)
		dsn := fmt.Sprintf("%s.db?cache=shared&_fk=1", config.DBName)
		DB, errDB = gorm.Open(sqlite.Open(dsn), &gorm.Config{
			Logger: logger.Default.LogMode(logger.Info),
		})
		if errDB != nil {
			log.Fatalf("Error connecting to SQLite database: %v", errDB)
		}
		log.Println("SQLite database connected successfully!")
		return DB
	}

	// MySQL connection (default)
	// First connect without database to create it if not exists (MySQL)
	dsnWithoutDB := fmt.Sprintf("%s:%s@tcp(%s:%s)/?charset=utf8mb4&parseTime=True&loc=Local",
		config.DBUser,
		config.DBPassword,
		config.DBHost,
		config.DBPort,
	)

	db, err := gorm.Open(mysql.Open(dsnWithoutDB), &gorm.Config{
		Logger: logger.Default.LogMode(logger.Info),
	})
	if err != nil {
		log.Printf("Error connecting to MySQL: %v", err)
	} else {
		// Create database if not exists
		createDBSQL := fmt.Sprintf("CREATE DATABASE IF NOT EXISTS %s CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci", config.DBName)
		db.Exec(createDBSQL)
		sqlDB, _ := db.DB()
		sqlDB.Close()
	}

	// Now connect with the database
	dsn := fmt.Sprintf("%s:%s@tcp(%s:%s)/%s?charset=utf8mb4&parseTime=True&loc=Local",
		config.DBUser,
		config.DBPassword,
		config.DBHost,
		config.DBPort,
		config.DBName,
	)

	DB, errDB = gorm.Open(mysql.Open(dsn), &gorm.Config{
		Logger: logger.Default.LogMode(logger.Info),
	})

	if errDB != nil {
		log.Fatalf("Error connecting to database: %v", errDB)
	}

	log.Println("MySQL database connected successfully!")
	return DB
}

// GetDB returns the database connection
func GetDB() *gorm.DB {
	return DB
}
