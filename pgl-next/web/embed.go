// Package web holds the embedded browser UI served by pgl-server.
package web

import "embed"

//go:embed all:dist
var Assets embed.FS
