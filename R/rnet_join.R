#' Join route networks
#'
#' This is a spatial join function that is enables adding columns to a
#' 'target' route network from a 'source' route
#' network that contains the base geometry, e.g. from OSM
#'
#' The output is an sf object containing polygons representing
#' buffers around the route network in `rnet_x`.
#' The examples below demonstrate how to join attributes from
#' a route network object created with the function [overline()] onto
#' OSM geometries.
#'
#' Note: The main purpose of this function is to join an ID from `rnet_x`
#' onto `rnet_y`. Subsequent steps, e.g. with [dplyr::inner_join()]
#' are needed to join the attributes back onto `rnet_x`.
#' There are rarely 1-to-1 relationships between spatial network geometries
#' so we take care when using this function.
#'
#' See [#505](https://github.com/ropensci/stplanr/issues/505) for details
#' and a link to an interactive example of inputs and outputs shown below.
#'
#' @param rnet_x Target route network, the output will have the same geometries
#'   as features in this object.
#' @param rnet_y Source route network. Columns from this route network object will
#'   be copied across to the new network.
#' @param dist The buffer width around rnet_y in meters. 1 m by default.
#' @param length_y Add a new column called `length_y`? Useful when joining based on
#'   length of segments (e.g. weighted mean). `TRUE` by default.
#' @param key_column The index of the key (unique identifier) column in `rnet_x`.
#' @param subset_x Subset the source route network by the target network before
#'   creating buffers? This can lead to faster and better results. Default:
#'   `TRUE`.
#' @param dist_subset The buffer distance in m to apply when breaking up the
#'   source object `rnet_y`. Default: 5.
#' @param segment_length Should the source route network be split?
#'   `0` by default, meaning no splitting. Values above 0 split the source
#'   into linestrings with a max distance. Around 5 (m) may be a sensible
#'   default for many use cases, the smaller the value the slower the process.
#' @param endCapStyle Type of buffer. See `?sf::st_buffer` for details
#' @param ... Additional arguments passed to `rnet_subset`.
#' @examples
#' library(sf)
#' library(dplyr)
#' # Uncomment for interactive examples:
#' plot(route_network_small["flow"])
#' plot(osm_net_example$geometry, lwd = 5, col = "grey")
#' plot(route_network_small["flow"], add = TRUE)
#' rnetj = rnet_join(osm_net_example, route_network_small, dist = 9)
#' rnetj2 = rnet_join(osm_net_example, route_network_small, dist = 9, segment_length = 10)
#' # library(mapview)
#' # mapview(rnetj, zcol = "flow") +
#' #   mapview(rnetj2, zcol = "flow") +
#' #   mapview(route_network_small, zcol = "flow")
#' plot(sf::st_geometry(rnetj))
#' plot(rnetj["flow"], add = TRUE)
#' plot(rnetj2["flow"], add = TRUE)
#' plot(route_network_small["flow"], add = TRUE)
#' summary(rnetj2$length_y)
#' rnetj_summary = rnetj2 %>%
#'   filter(!is.na(length_y)) %>%
#'   sf::st_drop_geometry() %>%
#'   group_by(osm_id) %>%
#'     summarise(
#'       flow = weighted.mean(flow, length_y, na.rm = TRUE),
#'       )
#' osm_joined_rnet = left_join(osm_net_example, rnetj_summary)
#' plot(sf::st_geometry(route_network_small))
#' plot(route_network_small["flow"], lwd = 3, add = TRUE)
#' plot(sf::st_geometry(osm_joined_rnet), add = TRUE)
#' plot(osm_joined_rnet[c("flow")], lwd = 9, add = TRUE)
#' # Improve fit between geometries and performance by subsetting rnet_x
#' osm_subset = rnet_subset(osm_net_example, route_network_small, dist = 5)
#' osm_joined_rnet = left_join(osm_subset, rnetj_summary)
#' plot(route_network_small["flow"])
#' plot(osm_joined_rnet[c("flow")])
#' # mapview(joined_network) +
#' #   mapview(route_network_small)
#' @export
rnet_join = function(rnet_x, rnet_y, dist = 5, length_y = TRUE, key_column = 1,
                     subset_x = TRUE, dist_subset = 5, segment_length = 0,
                     endCapStyle = "FLAT", ...) {
  if (subset_x) {
    rnet_x = rnet_subset(rnet_x, rnet_y, dist = dist_subset, ...)
  }
  rnet_x_buffer = geo_buffer(rnet_x, dist = dist, nQuadSegs = 2, endCapStyle = endCapStyle)
  if (segment_length > 0) {
    rnet_y = line_segment(rnet_y, segment_length = segment_length)
  }
  if (length_y) {
    rnet_y$length_y = as.numeric(sf::st_length(rnet_y))
  }
  rnet_y_centroids = sf::st_centroid(rnet_y)
  rnetj = sf::st_join(rnet_x_buffer[key_column], rnet_y_centroids)
  rnetj
}

#' Subset one route network based on overlaps with another
#'
#' @param rnet_x The route network to be subset
#' @param rnet_y The subsetting route network
#' @param dist The buffer width around y in meters. 1 m by default.
#' @param crop Crop `rnet_x`? `TRUE` is the default
#' @param min_length Segments shorter than this multiple of dist
#'   *and* which were longer
#'   before the cropping process will be removed. 3 by default.
#' @param rm_disconnected Remove ways that are
#' @export
rnet_subset = function(rnet_x, rnet_y, dist = 10, crop = TRUE, min_length = 0, rm_disconnected = TRUE) {
  rnet_x$length_x_original = as.numeric(sf::st_length(rnet_x))
  rnet_y_union = sf::st_union(rnet_y)
  rnet_y_buffer = stplanr::geo_buffer(rnet_y_union, dist = dist, nQuadSegs = 2)
  if(crop) {
    rnet_x = sf::st_intersection(rnet_x, rnet_y_buffer)
    rnet_x = line_cast(rnet_x)
  } else {
    rnet_x = rnet_x[rnet_y_buffer, , op = sf::st_within]
  }
  if(min_length > 0) {
    rnet_x = rnet_x[as.numeric(sf::st_length(rnet_x)) > min_length, ]
  }
  if(rm_disconnected) {
    rnet_x = rnet_connected(rnet_x)
  }
  rnet_x
}

#' Convert multilinestring object into linestrings
#'
#' Without losing vertices
#'
#' @param x Linestring object
#' @export
line_cast = function(x) {
  sf::st_cast(sf::st_cast(x, "MULTILINESTRING"), "LINESTRING")
}

#' Merge route networks, keeping attributes with aggregating functions
#'
#' @inheritParams rnet_join
#' @param sum_flows Should flows be summed? `TRUE` by default.
#' @param funs A named list of functions to apply to named columns, e.g.:
#'   `list(flow = sum, length = mean)`. The default is to sum all numeric
#'   columns.
#' @param ... Additional arguments passed to `rnet_join`.
#' @export
#' @examples
#' # The target object
#' rnet_x = rnet_subset(osm_net_example[1], route_network_small)
#' # The source object:
#' rnet_y = route_network_small["flow"]
#' rnet_y$quietness = rnorm(nrow(rnet_y))
#' funs = list(flow = sum, quietness = mean)
#' rnet_merged = rnet_merge(rnet_x[1], rnet_y[c("flow", "quietness")],
#'                          dist = 9, segment_length = 20, funs = funs)
#' plot(rnet_y["flow"])
#' plot(rnet_merged["flow"])
#'
#' # Larger example
#' system("gh release list")
#' system("gh release upload v1.0.2 rnet_*")
#' # List the files released in v1.0.2:
#' # system("gh release download v1.0.2")
#' # rnet_x = sf::read_sf("rnet_x_ed.geojson")
#' # rnet_y = sf::read_sf("rnet_y_ed.geojson")
#' # rnet_merged = rnet_merge(rnet_x, rnet_y, dist = 9, segment_length = 20, funs = funs)
#' @return An sf object with the same geometry as `rnet_x`
rnet_merge <- function(rnet_x, rnet_y, dist = 5, funs = NULL, sum_flows = TRUE, dist_subset = 20, ...) {
  if (is.null(funs)) {
    funs = list()
    for (col in names(rnet_y)) {
      if (is.numeric(rnet_y[[col]])) {
        funs[[col]] = sum
      }
    }
  }
  sum_cols = sapply(funs, function(f) identical(f, sum))
  sum_cols = names(funs)[which(sum_cols)]
  rnetj = rnet_join(rnet_x, rnet_y, dist = dist, dist_subset = dist_subset, ...)
  names(rnetj)
  rnetj_df = sf::st_drop_geometry(rnetj)
  # Apply functions to columns with lapply:
  res_list = lapply(seq(length(funs)), function(i) {
    # i = 1
    nm = names(funs[i])
    fn = funs[[i]]

    if (identical(fn, sum) && sum_flows) {
      res = rnetj_df %>%
        dplyr::group_by_at(1) %>%
        dplyr::summarise(dplyr::across(dplyr::matches(nm), function(x) sum(x * length_y)))
    } else {
      res = rnetj_df %>%
        dplyr::group_by_at(1) %>%
        dplyr::summarise(dplyr::across(dplyr::matches(nm), fn))
    }
    names(res)[2] = nm
    if(i > 1) {
      res = res[-1]
    }
    res
  })
  res_df = dplyr::bind_cols(res_list)
  res_sf = dplyr::left_join(rnet_x, res_df)
  if (sum_flows) {
    res_sf$length_x = as.numeric(sf::st_length(res_sf))
    for(i in sum_cols) {
      # TODO: deduplicate
      length_y = as.numeric(sf::st_length(rnet_y))
      # i = sum_cols[1]
      res_sf[[i]] = res_sf[[i]] / res_sf$length_x
      over_estimate = sum(res_sf[[i]] * res_sf$length_x, na.rm = TRUE) /
        sum(rnet_y[[i]] * length_y, na.rm = TRUE)
      res_sf[[i]] = res_sf[[i]] / over_estimate
    }
  }
  res_sf
}
