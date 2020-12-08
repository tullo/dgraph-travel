package handlers

import (
	"context"
	"fmt"
	"log"
	"net/http"
	"time"

	"github.com/dgraph-io/travel/business/data"
	"github.com/dgraph-io/travel/business/data/schema"
	"github.com/dgraph-io/travel/business/loader"
	"github.com/dgraph-io/travel/foundation/web"
	"github.com/pkg/errors"
)

type feedGroup struct {
	log          *log.Logger
	gqlConfig    data.GraphQLConfig
	loaderConfig loader.Config
}

func (fg *feedGroup) upload(ctx context.Context, w http.ResponseWriter, r *http.Request) error {
	var request schema.UploadFeedRequest
	if err := web.Decode(r, &request); err != nil {
		return errors.Wrap(err, "decoding request")
	}

	v, ok := ctx.Value(web.KeyValues).(*web.Values)
	if !ok {
		return web.NewShutdownError("web value missing from context")
	}

	go func() {
		fg.log.Printf("%s: started G: %s %s -> %s",
			v.TraceID,
			r.Method, r.URL.Path, r.RemoteAddr,
		)

		search := loader.Search{
			CityName:    request.CityName,
			CountryCode: request.CountryCode,
			Lat:         request.Lat,
			Lng:         request.Lng,
		}
		if err := loader.UpdateData(fg.log, fg.gqlConfig, v.TraceID, fg.loaderConfig, search); err != nil {
			fg.log.Printf("%s: completed G: %s %s -> %s (%d) (%s) : ERROR : %v",
				v.TraceID,
				r.Method, r.URL.Path, r.RemoteAddr,
				v.StatusCode, time.Since(v.Now), err,
			)
			return
		}

		fg.log.Printf("%s: completed G: %s %s -> %s (%d) (%s)",
			v.TraceID,
			r.Method, r.URL.Path, r.RemoteAddr,
			v.StatusCode, time.Since(v.Now),
		)
	}()

	resp := schema.UploadFeedResponse{
		CountryCode: request.CountryCode,
		CityName:    request.CityName,
		Lat:         request.Lat,
		Lng:         request.Lng,
		Message:     fmt.Sprintf("Uploading data for city %q [%f,%f] in country %q", request.CityName, request.Lat, request.Lng, request.CountryCode),
	}
	return web.Respond(ctx, w, resp, http.StatusOK)
}
