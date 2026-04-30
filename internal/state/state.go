package state

import (
	"encoding/json"
	"os"
	"path/filepath"
)

type Current struct {
	Name     string  `json:"name"`
	Host     string  `json:"host"`
	Network  string  `json:"network"`
	Security string  `json:"security"`
	Link     string  `json:"link"`
	TestedAt string  `json:"tested_at"`
	Port     int     `json:"port"`
	Mbps     float64 `json:"mbps"`
}

func SaveJSON(dir, name string, v any) error {
	if err := os.MkdirAll(dir, 0700); err != nil {
		return err
	}
	b, err := json.MarshalIndent(v, "", "  ")
	if err != nil {
		return err
	}
	return os.WriteFile(filepath.Join(dir, name), append(b, '\n'), 0600)
}
func LoadCurrent(dir string) (Current, error) {
	var c Current
	b, err := os.ReadFile(filepath.Join(dir, "current-node.json"))
	if err != nil {
		return c, err
	}
	return c, json.Unmarshal(b, &c)
}
