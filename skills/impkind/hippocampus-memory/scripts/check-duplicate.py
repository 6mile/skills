#!/usr/bin/env python3
"""
Check if a memory already exists (fuzzy match).
Returns existing memory ID if similar (>70% keyword overlap), else empty.

Usage: check-duplicate.py "memory content" [keywords as JSON array]
"""
import sys
import json
import re
from pathlib import Path

def extract_keywords(text):
    """Extract meaningful keywords from text."""
    # Lowercase and remove punctuation
    text = text.lower()
    text = re.sub(r'[^\w\s]', ' ', text)
    words = text.split()
    
    # Filter stopwords and short words
    stopwords = {'the', 'a', 'an', 'is', 'are', 'was', 'were', 'be', 'been', 
                 'being', 'have', 'has', 'had', 'do', 'does', 'did', 'will',
                 'would', 'could', 'should', 'may', 'might', 'must', 'shall',
                 'can', 'to', 'of', 'in', 'for', 'on', 'with', 'at', 'by',
                 'from', 'as', 'into', 'through', 'during', 'before', 'after',
                 'above', 'below', 'between', 'under', 'again', 'further',
                 'then', 'once', 'here', 'there', 'when', 'where', 'why',
                 'how', 'all', 'each', 'few', 'more', 'most', 'other', 'some',
                 'such', 'no', 'nor', 'not', 'only', 'own', 'same', 'so',
                 'than', 'too', 'very', 'just', 'and', 'but', 'or', 'if',
                 'this', 'that', 'these', 'those', 'i', 'me', 'my', 'we',
                 'our', 'you', 'your', 'he', 'him', 'his', 'she', 'her',
                 'it', 'its', 'they', 'them', 'their', 'what', 'which', 'who'}
    
    keywords = [w for w in words if len(w) > 2 and w not in stopwords]
    return set(keywords)

def similarity(kw1, kw2):
    """Calculate Jaccard similarity between two keyword sets."""
    if not kw1 or not kw2:
        return 0.0
    intersection = len(kw1 & kw2)
    union = len(kw1 | kw2)
    return intersection / union if union > 0 else 0.0

def main():
    if len(sys.argv) < 2:
        print("", end="")
        return
    
    new_content = sys.argv[1]
    new_keywords = extract_keywords(new_content)
    
    # If keywords provided as JSON, use those instead
    if len(sys.argv) > 2:
        try:
            provided_kw = json.loads(sys.argv[2])
            if provided_kw:
                new_keywords = set(k.lower() for k in provided_kw)
        except:
            pass
    
    # Load existing memories
    index_path = Path.home() / '.openclaw' / 'workspace' / 'memory' / 'index.json'
    if not index_path.exists():
        print("", end="")
        return
    
    try:
        with open(index_path) as f:
            data = json.load(f)
    except:
        print("", end="")
        return
    
    memories = data.get('memories', [])
    
    # Find best match
    best_match = None
    best_score = 0.0
    threshold = 0.70
    
    for mem in memories:
        # Get keywords from existing memory
        existing_kw = set()
        if 'keywords' in mem:
            existing_kw = set(k.lower() for k in mem['keywords'])
        
        # Also extract from content
        content = mem.get('content', mem.get('text', ''))
        existing_kw.update(extract_keywords(content))
        
        # Calculate similarity
        score = similarity(new_keywords, existing_kw)
        
        if score > best_score:
            best_score = score
            best_match = mem.get('id', '')
    
    # Return match if above threshold
    if best_score >= threshold and best_match:
        print(f"{best_match}:{best_score:.2f}", end="")
    else:
        print("", end="")

if __name__ == '__main__':
    main()
