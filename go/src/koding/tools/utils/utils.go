package utils

import (
	cryptorand "crypto/rand"
	"encoding/binary"
	"encoding/hex"
	"net"
	"sort"
	"unicode/utf8"
)

const MaxInt = int(^uint(0) >> 1)

const RandomStringLength = 24 // 144 bit base64 encoded

func RandomString() string {
	return StringN(RandomStringLength)
}

func StringN(n int) string {
	p := make([]byte, n/2+1)
	cryptorand.Read(p)
	return hex.EncodeToString(p)[:n]
}

func NewIntPool(offset int, alreadyTaken []int) (<-chan int, chan<- int) {
	fetchChan := make(chan int)
	releaseChan := make(chan int)
	go func() {
		tail := offset
		unused := make([]int, 0)
		sort.Ints(alreadyTaken)
		for _, v := range alreadyTaken {
			for tail <= v {
				if tail != v {
					unused = append(unused, tail)
				}
				tail += 1
			}
		}
		for {
			if len(unused) == 0 {
				unused = append(unused, tail)
				tail += 1
			}
			select {
			case fetchChan <- unused[len(unused)-1]:
				unused = unused[:len(unused)-1]
			case i := <-releaseChan:
				unused = append(unused, i)
			}
		}
	}()
	return fetchChan, releaseChan
}

func IntToIP(v int) net.IP {
	ip := net.IPv4(0, 0, 0, 0)
	binary.BigEndian.PutUint32(ip[12:16], uint32(v))
	return ip
}

func IPToInt(ip net.IP) int {
	return int(binary.BigEndian.Uint32(ip[12:16]))
}

func FilterInvalidUTF8(buf []byte) []byte {
	i := 0
	j := 0
	for {
		r, l := utf8.DecodeRune(buf[i:])
		if l == 0 {
			break
		}
		if r < 0xD800 {
			if i != j {
				copy(buf[j:], buf[i:i+l])
			}
			j += l
		}
		i += l
	}
	return buf[:j]
}
