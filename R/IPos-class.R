### =========================================================================
### IPos objects
### -------------------------------------------------------------------------
###


setClass("IPos",
    contains="Ranges",
    representation(
        pos_runs="IRanges"
    )
)


### - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
### Getters
###

setMethod("length", "IPos", function(x) sum(width(x@pos_runs)))

setMethod("names", "IPos", function(x) NULL)

setReplaceMethod("names", "IPos",
    function(x, value)
    {
        if (!is.null(value))
            stop(class(x), " objects don't accept names")
        x
    }
)

setGeneric("pos", function(x) standardGeneric("pos"))
setMethod("pos", "IPos", function(x) as.integer(x@pos_runs))
setMethod("start", "IPos", function(x) pos(x))
setMethod("end", "IPos", function(x) pos(x))
setMethod("width", "IPos", function(x) rep.int(1L, length(x)))


### - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
### Collapse runs of "stitchable integer ranges"
###
### In a Ranges object 'x', 2 ranges x[i] and x[i+1] are "stitchable" if
### start(x[i+1]) == end(x[i])+1. For example, in the following object:
###   1: .....xxxx.............
###   2: ...xx.................
###   3: .........xxx..........
###   4: ............xxxxxx....
###   5: ..................x...
### x[3] and x[4] are stitchable, and x[4] and x[5] are stitchable. So
### x[3], x[4], and x[5] form a run of "stitchable ranges" that will collapse
### into the following single range after stitching:
###      .........xxxxxxxxxx...
### Note that x[1] and x[3] are not stitchable because they are not
### consecutive vector elements (but they would if we removed x[2]).

### stitch_Ranges() below takes any Ranges derivative and returns an IRanges
### object (so is NOT an endomorphism). Note that this transformation
### preserves 'sum(width(x))'.
### Also note that this is an "inter range transformation". However unlike
### range(), reduce(), gaps(), or disjoin(), its result depends on the order
### of the elements in the input vector. It's also idempotent like range(),
### reduce(), and disjoin() (gaps() is not).

### TODO: Define and export stitch() generic and method for Ranges objects
### (in inter-range-methods.R).
### Maybe it would also make sense to have an isStitched() generic like we
### have isDisjoint() to provide a quick and easy way to check the state of
### the object before applying the transformation to it. In theory each
### idempotent inter range transformation could have a "state checker" so
### maybe add isReduced() too (range() probably doesn't need one).

stitch_Ranges <- function(x)
{
    if (length(x) == 0L)
        return(IRanges())
    x_start <- start(x)
    x_end <- end(x)

    ## Find runs of stitchable elements along 'x'.
    ## Each run is described by the indices of its first ('run_from') and
    ## last ('run_to') elements in 'x'.
    ## The runs form a partitioning of 'x'.
    new_run_idx <- which(x_start[-1L] != x_end[-length(x)] + 1L)
    run_from <- c(1L, new_run_idx + 1L)
    run_to <- c(new_run_idx, length(x))

    IRanges(x_start[run_from], x_end[run_to])
}

### The runs of positions in an IPos object are guaranteed to be stitched.
stitch_IPos <- function(x) x@pos_runs


### - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
### Validity
###

### TODO


### - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
### Constructor
###

### Note that if 'pos_runs' is an IPos instance with no metadata or metadata
### columns, then 'identical(IPos(pos_runs), pos_runs)' is TRUE.
IPos <- function(pos_runs=IRanges())
{
    if (!is(pos_runs, "Ranges"))
        pos_runs <- as(pos_runs, "Ranges", strict=FALSE)
    suppressWarnings(ans_len <- sum(width(pos_runs)))
    if (is.na(ans_len))
        stop("too many positions in 'pos_runs'")
    pos_runs <- stitch_Ranges(pos_runs)
    pos_runs <- pos_runs[width(pos_runs) != 0L]
    new2("IPos", pos_runs=pos_runs, check=FALSE)
}


### - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
### Coercion
###

.from_Ranges_to_IPos <- function(from)
{
    if (!all(width(from) == 1L))
        stop(wmsg("all the ranges in the ", class(from), " object to ",
                  "coerce to IPos must have a width of 1"))
    if (!is.null(names(from)))
        warning(wmsg("because an IPos object cannot hold them, the names ",
                     "on the ", class(from), " object couldn't be ",
                     "propagated during its coercion to IPos"))
    ans <- IPos(from)
    mcols(ans) <- mcols(from)
    ans
}
setAs("Ranges", "IPos", .from_Ranges_to_IPos)

setAs("ANY", "IPos", function(from) .from_Ranges_to_IPos(as(from, "Ranges")))

### The "as.data.frame" method for Ranges objects works on an IPos object
### but returns a data.frame with identical "start" and "end" columns, and
### a "width" column filled with 1. We overwrite it to return a data.frame
### with a "pos" column instead of the "start" and "end" columns, and no
### "width" column.
### TODO: Turn this into an S3/S4 combo for as.data.frame.IPos
setMethod("as.data.frame", "IPos",
    function(x, row.names=NULL, optional=FALSE, ...)
    {
        ans <- data.frame(pos=pos(x), stringsAsFactors=FALSE)
        x_mcols <- mcols(x)
        if (!is.null(x_mcols))
            ans <- cbind(ans, as.data.frame(x_mcols))
        ans
    }
)


### - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
### Subsetting
###

### NOT exported but used in the GenomicRanges package.
### 'pos_runs' must be an IRanges or GRanges object or any range-based
### object as long as it supports start(), end(), width(), and is subsettable.
### 'i' must be a Ranges object with no zero-width ranges.
extract_pos_runs_by_ranges <- function(pos_runs, i)
{
    map <- S4Vectors:::map_ranges_to_runs(width(pos_runs),
                                          start(i), width(i))
    ## Because 'i' has no zero-width ranges, 'mapped_range_span' cannot
    ## contain zeroes and so 'mapped_range_Ltrim' and 'mapped_range_Rtrim'
    ## cannot contain garbbage.
    mapped_range_offset <- map[[1L]]
    mapped_range_span <- map[[2L]]
    mapped_range_Ltrim <- map[[3L]]
    mapped_range_Rtrim <- map[[4L]]
    run_idx <- S4Vectors:::fancy_mseq(mapped_range_span,
                                      mapped_range_offset)
    pos_runs <- pos_runs[run_idx]
    if (length(run_idx) != 0L) {
        Rtrim_idx <- cumsum(mapped_range_span)
        Ltrim_idx <- c(1L, Rtrim_idx[-length(Rtrim_idx)] + 1L)
        trimmed_start <- start(pos_runs)[Ltrim_idx] +
                         mapped_range_Ltrim
        trimmed_end <- end(pos_runs)[Rtrim_idx] - mapped_range_Rtrim
        start(pos_runs)[Ltrim_idx] <- trimmed_start
        end(pos_runs)[Rtrim_idx] <- trimmed_end
        suppressWarnings(new_len <- sum(width(pos_runs)))
        if (is.na(new_len))
            stop("subscript is too big")
    }
    pos_runs
}

setMethod("extractROWS", "IPos",
    function(x, i)
    {
        i <- normalizeSingleBracketSubscript(i, x, as.NSBS=TRUE)
        ## TODO: Maybe make this the coercion method from NSBS to Ranges.
        if (is(i, "RangesNSBS")) {
            ir <- i@subscript
            ir <- ir[width(ir) != 0L]
        } else {
            ir <- as(as.integer(i), "IRanges")
        }
        new_pos_runs <- extract_pos_runs_by_ranges(x@pos_runs, ir)
        x@pos_runs <- stitch_Ranges(new_pos_runs)
        mcols(x) <- extractROWS(mcols(x), i)
        x
    }
)


### - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
### Show
###

.make_naked_matrix_from_IPos <- function(x)
{
    x_len <- length(x)
    x_mcols <- mcols(x)
    x_nmc <- if (is.null(x_mcols)) 0L else ncol(x_mcols)
    ans <- cbind(pos=as.character(pos(x)))
    if (x_nmc > 0L) {
        tmp <- do.call(data.frame, c(lapply(x_mcols, showAsCell),
                                     list(check.names=FALSE)))
        ans <- cbind(ans, `|`=rep.int("|", x_len), as.matrix(tmp))
    }
    ans
}

show_IPos <- function(x, margin="", print.classinfo=FALSE)
{
    x_class <- class(x)
    x_len <- length(x)
    x_mcols <- mcols(x)
    x_nmc <- if (is.null(x_mcols)) 0L else ncol(x_mcols)
    cat(x_class, " object with ",
        x_len, " ", ifelse(x_len == 1L, "position", "positions"),
        " and ",
        x_nmc, " metadata ", ifelse(x_nmc == 1L, "column", "columns"),
        ":\n", sep="")
    ## S4Vectors:::makePrettyMatrixForCompactPrinting() assumes that head()
    ## and tail() work on 'xx'.
    xx <- as(x, "IPos")
    out <- S4Vectors:::makePrettyMatrixForCompactPrinting(xx,
                .make_naked_matrix_from_IPos)
    if (print.classinfo) {
        .COL2CLASS <- c(pos="integer")
        classinfo <-
            S4Vectors:::makeClassinfoRowForCompactPrinting(x, .COL2CLASS)
        ## A sanity check, but this should never happen!
        stopifnot(identical(colnames(classinfo), colnames(out)))
        out <- rbind(classinfo, out)
    }
    if (nrow(out) != 0L)
        rownames(out) <- paste0(margin, rownames(out))
    ## We set 'max' to 'length(out)' to avoid the getOption("max.print")
    ## limit that would typically be reached when 'showHeadLines' global
    ## option is set to Inf.
    print(out, quote=FALSE, right=TRUE, max=length(out))
}

setMethod("show", "IPos",
    function(object) show_IPos(object, margin="  ", print.classinfo=TRUE)
)


### - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
### Combining
###
### Note that supporting "[" and "c" makes "[<-" work out-of-the-box!
###

### 'Class' must be "IPos" or the name of a concrete IPos subclass.
### 'objects' must be a list of IPos objects.
### Returns an instance of class 'Class'.
combine_IPos_objects <- function(Class, objects,
                                 use.names=TRUE, ignore.mcols=FALSE)
{
    if (!isSingleString(Class))
        stop("'Class' must be a single character string")
    if (!extends(Class, "IPos"))
        stop("'Class' must be the name of a class that extends IPos")
    if (!is.list(objects))
        stop("'objects' must be a list")
    if (!isTRUEorFALSE(use.names))
        stop("'use.names' must be TRUE or FALSE")
    ### TODO: Support 'use.names=TRUE'.
    if (use.names)
        stop("'use.names=TRUE' is not supported yet")
    if (!isTRUEorFALSE(ignore.mcols))
        stop("'ignore.mcols' must be TRUE or FALSE")

    if (length(objects) != 0L) {
        ## TODO: Implement (in C) fast 'elementIsNull(objects)' in S4Vectors
        ## that does 'sapply(objects, is.null, USE.NAMES=FALSE)', and use it
        ## here.
        null_idx <- which(sapply(objects, is.null, USE.NAMES=FALSE))
        if (length(null_idx) != 0L)
            objects <- objects[-null_idx]
    }
    if (length(objects) == 0L)
        return(new(Class))

    ## TODO: Implement (in C) fast 'elementIs(objects, class)' in S4Vectors
    ## that does 'sapply(objects, is, class, USE.NAMES=FALSE)', and use it
    ## here. 'elementIs(objects, "NULL")' should work and be equivalent to
    ## 'elementIsNull(objects)'.
    if (!all(sapply(objects, is, Class, USE.NAMES=FALSE)))
        stop("the objects to combine must be ", Class, " objects (or NULLs)")
    objects_names <- names(objects)
    names(objects) <- NULL  # so lapply(objects, ...) below returns an
                            # unnamed list

    ## Combine "pos_runs" slots.
    pos_runs_slots <- lapply(objects, function(x) x@pos_runs)
    ## TODO: Use combine_IRanges_objects() here when it's available.
    ans_pos_runs <- stitch_Ranges(do.call(c, pos_runs_slots))

    suppressWarnings(ans_len <- sum(width(ans_pos_runs)))
    if (is.na(ans_len))
        stop("too many genomic positions to combine")

    ## Combine "mcols" slots.
    if (ignore.mcols) {
        ans_mcols <- NULL
    } else  {
        ans_mcols <- do.call(S4Vectors:::rbind_mcols, objects)
    }

    ## Make 'ans' and return it.
    new2(Class, pos_runs=ans_pos_runs, elementMetadata=ans_mcols, check=FALSE)
}

setMethod("c", "IPos",
    function (x, ..., ignore.mcols=FALSE, recursive=FALSE)
    {
        if (!identical(recursive, FALSE))
            stop("\"c\" method for IPos objects ",
                 "does not support the 'recursive' argument")
        if (missing(x)) {
            objects <- list(...)
            x <- objects[[1L]]
        } else {
            objects <- list(x, ...)
        }
        combine_IPos_objects(class(x), objects,
                             use.names=FALSE,
                             ignore.mcols=ignore.mcols)
    }
)

