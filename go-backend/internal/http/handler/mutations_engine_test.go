package handler

import "testing"

func TestNormalizeForwardEngine(t *testing.T) {
	tests := []struct {
		name string
		in   string
		want string
	}{
		{name: "empty to auto", in: "", want: "auto"},
		{name: "spaces to auto", in: "   ", want: "auto"},
		{name: "gost", in: "gost", want: "gost"},
		{name: "auto", in: "auto", want: "auto"},
		{name: "nftables", in: "nftables", want: "nftables"},
		{name: "realm", in: "realm", want: "realm"},
		{name: "upper case", in: "NFTABLES", want: "nftables"},
		{name: "unknown fallback", in: "something-else", want: "auto"},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			got := normalizeForwardEngine(tc.in)
			if got != tc.want {
				t.Fatalf("normalizeForwardEngine(%q) = %q, want %q", tc.in, got, tc.want)
			}
		})
	}
}
