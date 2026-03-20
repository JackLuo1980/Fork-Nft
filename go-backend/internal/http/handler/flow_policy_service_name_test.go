package handler

import "testing"

func TestParseFlowServiceIDsAcceptsProtocolSuffix(t *testing.T) {
	cases := []struct {
		name       string
		service    string
		forwardID  int64
		userID     int64
		userTunnel int64
	}{
		{
			name:       "tcp suffix",
			service:    "20_2_10_tcp",
			forwardID:  20,
			userID:     2,
			userTunnel: 10,
		},
		{
			name:       "udp suffix",
			service:    "30_3_11_udp",
			forwardID:  30,
			userID:     3,
			userTunnel: 11,
		},
		{
			name:       "no suffix",
			service:    "40_4_12",
			forwardID:  40,
			userID:     4,
			userTunnel: 12,
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			forwardID, userID, userTunnelID, ok := parseFlowServiceIDs(tc.service)
			if !ok {
				t.Fatalf("expected %s to be parsed", tc.service)
			}
			if forwardID != tc.forwardID || userID != tc.userID || userTunnelID != tc.userTunnel {
				t.Fatalf("unexpected parse result: got (%d,%d,%d), want (%d,%d,%d)",
					forwardID, userID, userTunnelID, tc.forwardID, tc.userID, tc.userTunnel)
			}
		})
	}
}
