{-# LANGUAGE CPP #-}

#define DO_NOT_EDIT (doNotEdit __FILE__ __LINE__)

-- | Generates code for HTML tags.
--
module Util.GenerateHtmlCombinators where

import Control.Arrow ((&&&))
import Data.List (sort, sortBy, intersperse, intercalate)
import Data.Ord (comparing)
import System.Directory (createDirectoryIfMissing)
import System.FilePath ((</>), (<.>))
import Data.Map (Map)
import qualified Data.Map as M
import Data.Char (toLower)
import qualified Data.Set as S

import Util.Sanitize (sanitize, prelude)

-- | Datatype for an HTML variant.
--
data HtmlVariant = HtmlVariant
    { version     :: [String]
    , docType     :: [String]
    , parents     :: [String]
    , leafs       :: [String]
    , attributes  :: [String]
    , selfClosing :: Bool
    } deriving (Eq)

instance Show HtmlVariant where
    show = map toLower . intercalate "-" . version

-- | Get the full module name for an HTML variant.
--
getModuleName :: HtmlVariant -> String
getModuleName = ("Text.Blaze." ++) . intercalate "." . version

-- | Get the attribute module name for an HTML variant.
--
getAttributeModuleName :: HtmlVariant -> String
getAttributeModuleName = (++ ".Attributes") . getModuleName

-- | Check if a given name causes a name clash.
--
isNameClash :: HtmlVariant -> String -> Bool
isNameClash v t
    -- Both an element and an attribute
    | (t `elem` parents v || t `elem` leafs v) && t `elem` attributes v = True
    -- Already a prelude function
    | sanitize t `S.member` prelude = True
    | otherwise = False

-- | Write an HTML variant.
--
writeHtmlVariant :: HtmlVariant -> IO ()
writeHtmlVariant htmlVariant = do
    -- Make a directory.
    createDirectoryIfMissing True basePath

    let tags =  zip parents' (repeat makeParent)
             ++ zip leafs' (repeat (makeLeaf $ selfClosing htmlVariant))
        sortedTags = sortBy (comparing fst) tags
        appliedTags = map (\(x, f) -> f x) sortedTags

    -- Write the main module.
    writeFile' (basePath <.> "hs") $ removeTrailingNewlines $ unlines
        [ DO_NOT_EDIT
        , "{-# LANGUAGE OverloadedStrings #-}"
        , "-- | This module exports HTML combinators used to create documents."
        , "--"
        , exportList modulName $ "module Text.Blaze.Html"
                               : "docType"
                               : "docTypeHtml"
                               : map (sanitize . fst) sortedTags
        , DO_NOT_EDIT
        , "import Prelude ((>>), (.))"
        , ""
        , "import Text.Blaze"
        , "import Text.Blaze.Internal"
        , "import Text.Blaze.Html"
        , ""
        , makeDocType $ docType htmlVariant
        , makeDocTypeHtml $ docType htmlVariant
        , unlines appliedTags
        ]

    let sortedAttributes = sort attributes'

    -- Write the attribute module.
    writeFile' (basePath </> "Attributes.hs") $ removeTrailingNewlines $ unlines
        [ DO_NOT_EDIT
        , "-- | This module exports combinators that provide you with the"
        , "-- ability to set attributes on HTML elements."
        , "--"
        , "{-# LANGUAGE OverloadedStrings #-}"
        , exportList attributeModuleName $ map sanitize sortedAttributes
        , DO_NOT_EDIT
        , "import Prelude ()"
        , ""
        , "import Text.Blaze.Internal (Attribute, AttributeValue, attribute)"
        , ""
        , unlines (map makeAttribute sortedAttributes)
        ]
  where
    basePath  = "src" </> "Text" </> "Blaze" </> foldl1 (</>) version'
    modulName = getModuleName htmlVariant
    attributeModuleName = getAttributeModuleName htmlVariant
    attributes' = attributes htmlVariant
    parents'    = parents htmlVariant
    leafs'      = leafs htmlVariant
    version'    = version htmlVariant
    removeTrailingNewlines = reverse . drop 2 . reverse
    writeFile' file content = do
        putStrLn ("Generating " ++ file)
        writeFile file content

-- | Create a string, consisting of @x@ spaces, where @x@ is the length of the
-- argument.
--
spaces :: String -> String
spaces = flip replicate ' ' . length

-- | Join blocks of code with a newline in between.
--
unblocks :: [String] -> String
unblocks = unlines . intersperse "\n"

-- | A warning to not edit the generated code.
--
doNotEdit :: FilePath -> Int -> String
doNotEdit fileName lineNumber = init $ unlines
    [ "-- WARNING: The next block of code was automatically generated by"
    , "-- " ++ fileName ++ ":" ++ show lineNumber
    , "--"
    ]

-- | Generate an export list for a Haskell module.
--
exportList :: String   -- ^ Module name.
           -> [String] -- ^ List of functions.
           -> String   -- ^ Resulting string.
exportList _    []            = error "exportList without functions."
exportList name (f:functions) = unlines $
    [ "module " ++ name
    , "    ( " ++ f
    ] ++
    map ("    , " ++) functions ++
    [ "    ) where"]

-- | Generate a function for a doctype.
--
makeDocType :: [String] -> String
makeDocType lines' = unlines
    [ DO_NOT_EDIT
    , "-- | Combinator for the document type. This should be placed at the top"
    , "-- of every HTML page."
    , "--"
    , "-- Example:"
    , "--"
    , "-- > docType"
    , "--"
    , "-- Result:"
    , "--"
    , unlines (map ("-- > " ++) lines') ++ "--"
    , "docType :: Html  -- ^ The document type HTML."
    , "docType = preEscapedText " ++ show (unlines lines')
    , "{-# INLINE docType #-}"
    ]

-- | Generate a function for the HTML tag (including the doctype).
--
makeDocTypeHtml :: [String]  -- ^ The doctype.
                -> String    -- ^ Resulting combinator function.
makeDocTypeHtml lines' = unlines
    [ DO_NOT_EDIT
    , "-- | Combinator for the @\\<html>@ element. This combinator will also"
    , "-- insert the correct doctype."
    , "--"
    , "-- Example:"
    , "--"
    , "-- > docTypeHtml $ span $ toHtml \"foo\""
    , "--"
    , "-- Result:"
    , "--"
    , unlines (map ("-- > " ++) lines') ++ "-- > <html><span>foo</span></html>"
    , "--"
    , "docTypeHtml :: Html  -- ^ Inner HTML."
    , "            -> Html  -- ^ Resulting HTML."
    , "docTypeHtml inner = docType >> html inner"
    , "{-# INLINE docTypeHtml #-}"
    ]

-- | Generate a function for an HTML tag that can be a parent.
--
makeParent :: String -> String
makeParent tag = unlines
    [ DO_NOT_EDIT
    , "-- | Combinator for the @\\<" ++ tag ++ ">@ element."
    , "--"
    , "-- Example:"
    , "--"
    , "-- > " ++ function ++ " $ span $ toHtml \"foo\""
    , "--"
    , "-- Result:"
    , "--"
    , "-- > <" ++ tag ++ "><span>foo</span></" ++ tag ++ ">"
    , "--"
    , function        ++ " :: Html  -- ^ Inner HTML."
    , spaces function ++ " -> Html  -- ^ Resulting HTML."
    , function        ++ " = Parent \"" ++ tag ++ "\" \"<" ++ tag
                      ++ "\" \"</" ++ tag ++ ">\"" ++ modifier
    , "{-# INLINE " ++ function ++ " #-}"
    ]
  where
    function = sanitize tag
    modifier = if tag `elem` ["style", "script"] then " . external" else ""

-- | Generate a function for an HTML tag that must be a leaf.
--
makeLeaf :: Bool    -- ^ Make leaf tags self-closing
         -> String  -- ^ Tag for the combinator
         -> String  -- ^ Combinator code
makeLeaf closing tag = unlines
    [ DO_NOT_EDIT
    , "-- | Combinator for the @\\<" ++ tag ++ " />@ element."
    , "--"
    , "-- Example:"
    , "--"
    , "-- > " ++ function
    , "--"
    , "-- Result:"
    , "--"
    , "-- > <" ++ tag ++ " />"
    , "--"
    , function ++ " :: Html  -- ^ Resulting HTML."
    , function ++ " = Leaf \"" ++ tag ++ "\" \"<" ++ tag ++ "\" " ++ "\""
               ++ (if closing then " /" else "") ++ ">\" ()"
    , "{-# INLINE " ++ function ++ " #-}"
    ]
  where
    function = sanitize tag

-- | Generate a function for an HTML attribute.
--
makeAttribute :: String -> String
makeAttribute name = unlines
    [ DO_NOT_EDIT
    , "-- | Combinator for the @" ++ name ++ "@ attribute."
    , "--"
    , "-- Example:"
    , "--"
    , "-- > div ! " ++ function ++ " \"bar\" $ \"Hello.\""
    , "--"
    , "-- Result:"
    , "--"
    , "-- > <div " ++ name ++ "=\"bar\">Hello.</div>"
    , "--"
    , function        ++ " :: AttributeValue  -- ^ Attribute value."
    , spaces function ++ " -> Attribute       -- ^ Resulting attribute."
    , function        ++ " = attribute \"" ++ name ++ "\" \" "
                      ++ name ++ "=\\\"\""
    , "{-# INLINE " ++ function ++ " #-}"
    ]
  where
    function = sanitize name

-- | HTML 4.01 Strict.
-- A good reference can be found here: http://www.w3schools.com/tags/default.asp
--
html4Strict :: HtmlVariant
html4Strict = HtmlVariant
    { version = ["Html4", "Strict"]
    , docType =
        [ "<!DOCTYPE HTML PUBLIC \"-//W3C//DTD HTML 4.01//EN\""
        , "    \"http://www.w3.org/TR/html4/strict.dtd\">"
        ]
    , parents =
        [ "a", "abbr", "acronym", "address", "b", "bdo", "big", "blockquote"
        , "body" , "button", "caption", "cite", "code", "colgroup", "dd", "del"
        , "dfn", "div" , "dl", "dt", "em", "fieldset", "form", "h1", "h2", "h3"
        , "h4", "h5", "h6", "head", "html", "i", "ins" , "kbd", "label"
        , "legend", "li", "map", "noscript", "object", "ol", "optgroup"
        , "option", "p", "pre", "q", "samp", "script", "select", "small"
        , "span", "strong", "style", "sub", "sup", "table", "tbody", "td"
        , "textarea", "tfoot", "th", "thead", "title", "tr", "tt", "ul", "var"
        ]
    , leafs =
        [ "area", "br", "col", "hr", "link", "img", "input",  "meta", "param"
        ]
    , attributes =
        [ "abbr", "accept", "accesskey", "action", "align", "alt", "archive"
        , "axis", "border", "cellpadding", "cellspacing", "char", "charoff"
        , "charset", "checked", "cite", "class", "classid", "codebase"
        , "codetype", "cols", "colspan", "content", "coords", "data", "datetime"
        , "declare", "defer", "dir", "disabled", "enctype", "for", "frame"
        , "headers", "height", "href", "hreflang", "http-equiv", "id", "label"
        , "lang", "maxlength", "media", "method", "multiple", "name", "nohref"
        , "onabort", "onblur", "onchange", "onclick", "ondblclick", "onfocus"
        , "onkeydown", "onkeypress", "onkeyup", "onload", "onmousedown"
        , "onmousemove", "onmouseout", "onmouseover", "onmouseup", "onreset"
        , "onselect", "onsubmit", "onunload", "profile", "readonly", "rel"
        , "rev", "rows", "rowspan", "rules", "scheme", "scope", "selected"
        , "shape", "size", "span", "src", "standby", "style", "summary"
        , "tabindex", "title", "type", "usemap", "valign", "value", "valuetype"
        , "width"
        ]
    , selfClosing = False
    }

-- | HTML 4.0 Transitional
--
html4Transitional :: HtmlVariant
html4Transitional = HtmlVariant
    { version = ["Html4", "Transitional"]
    , docType =
        [ "<!DOCTYPE HTML PUBLIC \"-//W3C//DTD HTML 4.01 Transitional//EN\""
        , "    \"http://www.w3.org/TR/html4/loose.dtd\">"
        ]
    , parents = parents html4Strict ++
        [ "applet", "center", "dir", "font", "iframe", "isindex", "menu"
        , "noframes", "s", "u"
        ]
    , leafs = leafs html4Strict ++ ["basefont"]
    , attributes = attributes html4Strict ++
        [ "background", "bgcolor", "clear", "compact", "hspace", "language"
        , "noshade", "nowrap", "start", "target", "vspace"
        ]
    , selfClosing = False
    }

-- | HTML 4.0 FrameSet
--
html4FrameSet :: HtmlVariant
html4FrameSet = HtmlVariant
    { version = ["Html4", "FrameSet"]
    , docType =
        [ "<!DOCTYPE HTML PUBLIC \"-//W3C//DTD HTML 4.01 FrameSet//EN\""
        , "    \"http://www.w3.org/TR/html4/frameset.dtd\">"
        ]
    , parents = parents html4Transitional ++ ["frameset"]
    , leafs = leafs html4Transitional ++ ["frame"]
    , attributes = attributes html4Transitional ++
        [ "frameborder", "scrolling"
        ]
    , selfClosing = False
    }

-- | XHTML 1.0 Strict
--
xhtml1Strict :: HtmlVariant
xhtml1Strict = HtmlVariant
    { version = ["XHtml1", "Strict"]
    , docType =
        [ "<!DOCTYPE html PUBLIC \"-//W3C//DTD XHTML 1.0 Strict//EN\""
        , "    \"http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd\">"
        ]
    , parents = parents html4Strict
    , leafs = leafs html4Strict
    , attributes = attributes html4Strict
    , selfClosing = True
    }

-- | XHTML 1.0 Transitional
--
xhtml1Transitional :: HtmlVariant
xhtml1Transitional = HtmlVariant
    { version = ["XHtml1", "Transitional"]
    , docType =
        [ "<!DOCTYPE html PUBLIC \"-//W3C//DTD XHTML 1.0 Transitional//EN\""
        , "    \"http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd\">"
        ]
    , parents = parents html4Transitional
    , leafs = leafs html4Transitional
    , attributes = attributes html4Transitional
    , selfClosing = True
    }

-- | XHTML 1.0 FrameSet
--
xhtml1FrameSet :: HtmlVariant
xhtml1FrameSet = HtmlVariant
    { version = ["XHtml1", "FrameSet"]
    , docType =
        [ "<!DOCTYPE html PUBLIC \"-//W3C//DTD XHTML 1.0 FrameSet//EN\""
        , "    \"http://www.w3.org/TR/xhtml1/DTD/xhtml1-frameset.dtd\">"
        ]
    , parents = parents html4FrameSet
    , leafs = leafs html4FrameSet
    , attributes = attributes html4FrameSet
    , selfClosing = True
    }

-- | HTML 5.0
-- A good reference can be found here:
-- http://www.w3schools.com/html5/html5_reference.asp
--
html5 :: HtmlVariant
html5 = HtmlVariant
    { version = ["Html5"]
    , docType = ["<!DOCTYPE HTML>"]
    , parents =
        [ "a", "abbr", "address", "article", "aside", "audio", "b"
        , "bdo", "blockquote", "body", "button", "canvas", "caption", "cite"
        , "code", "colgroup", "command", "datalist", "dd", "del", "details"
        , "dfn", "div", "dl", "dt", "em", "fieldset", "figcaption", "figure"
        , "footer", "form", "h1", "h2", "h3", "h4", "h5", "h6", "head", "header"
        , "hgroup", "html", "i", "iframe", "ins", "kbd", "label"
        , "legend", "li", "main", "map", "mark", "menu", "meter", "nav"
        , "noscript", "object", "ol", "optgroup", "option", "output", "p"
        , "pre", "progress", "q", "rp", "rt", "ruby", "samp", "script"
        , "section", "select", "small", "span", "strong", "style", "sub"
        , "summary", "sup", "table", "tbody", "td", "textarea", "tfoot", "th"
        , "thead", "time", "title", "tr", "u", "ul", "var", "video"
        ]
    , leafs =
        -- http://www.whatwg.org/specs/web-apps/current-work/multipage/syntax.html#void-elements
        [ "area", "base", "br", "col", "embed", "hr", "img", "input", "keygen"
        , "link", "menuitem", "meta", "param", "source", "track", "wbr"
        ]
    , attributes =
        [ "accept", "accept-charset", "accesskey", "action", "alt", "async"
        , "autocomplete", "autofocus", "autoplay", "challenge", "charset"
        , "checked", "cite", "class", "cols", "colspan", "content"
        , "contenteditable", "contextmenu", "controls", "coords", "data"
        , "datetime", "defer", "dir", "disabled", "draggable", "enctype", "for"
        , "form", "formaction", "formenctype", "formmethod", "formnovalidate"
        , "formtarget", "headers", "height", "hidden", "high", "href"
        , "hreflang", "http-equiv", "icon", "id", "ismap", "item", "itemprop"
        , "itemscope", "itemtype"
        , "keytype", "label", "lang", "list", "loop", "low", "manifest", "max"
        , "maxlength", "media", "method", "min", "multiple", "name"
        , "novalidate", "onbeforeonload", "onbeforeprint", "onblur", "oncanplay"
        , "oncanplaythrough", "onchange", "oncontextmenu", "onclick"
        , "ondblclick", "ondrag", "ondragend", "ondragenter", "ondragleave"
        , "ondragover", "ondragstart", "ondrop", "ondurationchange", "onemptied"
        , "onended", "onerror", "onfocus", "onformchange", "onforminput"
        , "onhaschange", "oninput", "oninvalid", "onkeydown", "onkeyup"
        , "onload", "onloadeddata", "onloadedmetadata", "onloadstart"
        , "onmessage", "onmousedown", "onmousemove", "onmouseout", "onmouseover"
        , "onmouseup", "onmousewheel", "ononline", "onpagehide", "onpageshow"
        , "onpause", "onplay", "onplaying", "onprogress", "onpropstate"
        , "onratechange", "onreadystatechange", "onredo", "onresize", "onscroll"
        , "onseeked", "onseeking", "onselect", "onstalled", "onstorage"
        , "onsubmit", "onsuspend", "ontimeupdate", "onundo", "onunload"
        , "onvolumechange", "onwaiting", "open", "optimum", "pattern", "ping"
        , "placeholder", "preload", "pubdate", "radiogroup", "readonly", "rel"
        , "required", "reversed", "role", "rows", "rowspan", "sandbox", "scope"
        , "scoped", "seamless", "selected", "shape", "size", "sizes", "span"
        , "spellcheck", "src", "srcdoc", "start", "step", "style", "subject"
        , "summary", "tabindex", "target", "title", "type", "usemap", "value"
        , "width", "wrap", "xmlns"
        ]
    , selfClosing = False
    }

-- | XHTML 5.0
--
xhtml5 :: HtmlVariant
xhtml5 = HtmlVariant
    { version = ["XHtml5"]
    , docType = ["<!DOCTYPE html>"]
    , parents = parents html5
    , leafs = leafs html5
    , attributes = attributes html5
    , selfClosing = True
    }


-- | A map of HTML variants, per version, lowercase.
--
htmlVariants :: Map String HtmlVariant
htmlVariants = M.fromList $ map (show &&& id)
    [ html4Strict
    , html4Transitional
    , html4FrameSet
    , xhtml1Strict
    , xhtml1Transitional
    , xhtml1FrameSet
    , html5
    , xhtml5
    ]

main :: IO ()
main = mapM_ (writeHtmlVariant . snd) $ M.toList htmlVariants
