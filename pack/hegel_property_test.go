package pack

import (
	"bytes"
	"os"
	"path/filepath"
	"strconv"
	"testing"

	"github.com/stretchr/testify/require"
	"hegel.dev/go/hegel"
)

// TestPackRoundTripHegel states the same property as TestPackRoundTripProperty
// with the same blob shapes and bounds, using Hegel instead of Rapid.
// PACK_PROPERTY_CASES overrides the 40-case budget for comparisons.
func TestPackRoundTripHegel(t *testing.T) {
	key := testKey(21)
	crypter, err := NewCrypter(key)
	require.NoError(t, err)

	cases := 40
	if v := os.Getenv("PACK_PROPERTY_CASES"); v != "" {
		cases, err = strconv.Atoi(v)
		require.NoError(t, err)
	}

	blob := hegel.OneOf(
		hegel.Just([]byte{}),
		hegel.Binary(1, 1),
		hegel.Map(hegel.Integers(1, 2048), func(n int) []byte {
			return bytes.Repeat([]byte("pattern!"), n)
		}),
		hegel.Binary(0, 99),
	)
	blobSets := hegel.Lists(blob).MaxSize(99)

	for _, tc := range []struct {
		name    string
		crypter *Crypter
	}{
		{name: "plain"},
		{name: "encrypted", crypter: crypter},
	} {
		t.Run(tc.name, func(t *testing.T) {
			hegel.Test(t, func(ht *hegel.T) {
				blobs := hegel.Draw(ht, blobSets)
				dir := t.TempDir()
				w, err := NewWriter(dir, WriterOptions{Crypter: tc.crypter})
				require.NoError(ht, err)
				wrote := make([]Entry, 0, len(blobs))
				for _, b := range blobs {
					e, err := w.Append(b)
					require.NoError(ht, err)
					wrote = append(wrote, e)
				}
				path := filepath.Join(dir, w.ID()+".mvpack")
				_, err = w.Seal(path)
				require.NoError(ht, err)
				r, err := OpenReader(path, tc.crypter)
				require.NoError(ht, err)
				defer func() { _ = r.Close() }()
				got := r.Entries()
				require.Len(ht, got, len(blobs))
				for i, e := range got {
					require.Equal(ht, wrote[i], e, "entry %d", i)
					raw, err := r.ReadBlob(e)
					require.NoError(ht, err, "blob %d", i)
					require.Truef(ht, bytes.Equal(blobs[i], raw), "blob %d: got %x, want %x", i, raw, blobs[i])
				}
			}, hegel.WithTestCases(cases))
		})
	}
}
