package hello

import (
	"context"
	"log"
)

type PubSubMessage struct {
	Data []byte `json:"data"`
}

func HelloPubSub(ctx context.Context, m PubSubMessage) error {
	name := string(m.Data)
	log.Printf("Hello, %s!", name)
	return nil
}
