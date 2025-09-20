DOCX=Stage_3_Trait_Indices_Bill_Shipley_Review.docx
MD=Stage_3_trait_indices.md

.PHONY: all docx clean

all: docx

docx: $(DOCX)

$(DOCX): $(MD)
	pandoc -s "$(MD)" -o "$(DOCX)" --from gfm --metadata title="Trait-Based Ecosystem Service Indices — Stage 3"

clean:
	rm -f "$(DOCX)"

